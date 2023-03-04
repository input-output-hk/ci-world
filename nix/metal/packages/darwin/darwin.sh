#!/usr/bin/env bash
# Shebang above to satisfy standalone shellcheck outside of writeShellApplication wrapper
# set mode is -euo pipefail by default

ERRORS="$(mktemp -t darwin-errors-XXXXXX)"
err_report() {
  echo
  echo -e "${RED}ERROR:${NC}"
  echo "Error on line $1 on $(readlink -e "${BASH_SOURCE[0]}")"
  echo
  echo -e "${RED}Error output may additionally include:${NC}"
  cat "$ERRORS"
  rm -f "$ERRORS"
}

trap 'err_report $LINENO' ERR

# For parsing template updates:
# nix run nixpkgs#argbash -- parser.sh -o parser.sh --strip user-content
# shellcheck disable=SC1091,SC2154
source @parser@

MODE=${_arg_mode:?}
CONFIG=${_arg_config:?}
TARGET=${_arg_target:-}

RED='\033[1;91m'
GREEN='\033[1;92m'
YELLOW='\033[1;93m'
NC='\033[0m'
STATUS="${GREEN}Status:${NC}"

if [ -z "$TARGET" ]; then
  TARGET="$CONFIG"
fi

if ! [[ $MODE =~ ^deploy|send-keys$ ]]; then
  echo 'The MODE must be either "deploy" or "send-keys"'
  exit 1
fi

if [ "$MODE" = "deploy" ]; then
  echo -e "$STATUS Preparing to $MODE darwinConfigurations.$CONFIG to ssh://$TARGET ..."
  echo

  echo -e "$STATUS Obtaining nix-darwin derivation path for #darwinConfigurations.$CONFIG ..."
  DRV=$(nix path-info --derivation ".#darwinConfigurations.$CONFIG.config.system.build.toplevel" 2>"$ERRORS")

  echo -e "$STATUS Obtaining nix-darwin derivation system out path for #darwinConfigurations.$CONFIG ..."
  OUT=$(nix-store -q --binding out "$DRV" 2>"$ERRORS")
  echo

  echo "Derivation path to deploy is:"
  echo "$DRV"
  echo

  echo "Derivation system out path for the target system is:"
  echo "$OUT"
  echo

  # ssh:// for the copy is much faster than ssh-ng://
  echo -e "$STATUS Copying the darwinConfiguration derivation closure to the target machine ..."
  export NIX_SSHOPTS="-o StrictHostKeyChecking=accept-new PATH=/nix/var/nix/profiles/system/sw/bin/:\$PATH"
  echo "nix copy -L -v -s --to ssh://$TARGET --derivation $DRV"
  nix copy -L -v -s --to "ssh://$TARGET" --derivation "$DRV"
  echo

  # ssh-ng:// is required for building functionality of these derivations
  echo -e "$STATUS Building the darwinConfiguration on the target machine ..."
  echo "nix build -L -v $DRV --eval-store auto --store ssh-ng://$TARGET"
  nix build -L -v "$DRV" --eval-store auto --store "ssh-ng://$TARGET"
  echo

  echo -e "$STATUS Setting the system profile on the remote target to derivation system out path ..."
  echo "ssh $TARGET -- /run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set $OUT"
  ssh "$TARGET" -- "/run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set $OUT"
  echo

  echo -e "$STATUS Switching to the deployed profile on the target ..."
  echo "activating user..."
  ssh "$TARGET" -- "$OUT/activate-user"
  echo "activating system..."
  ssh "$TARGET" -- "$OUT/activate"
  echo

  echo -e "${GREEN}Deployment complete.${NC}"
fi

if [ "$MODE" = "send-keys" ]; then
  echo -e "$STATUS Preparing to $MODE for darwinConfigurations.$CONFIG to ssh://$TARGET ..."
  echo
  KEYS_JSON=$(nix eval --json ".#darwinConfigurations.$CONFIG.config.services.darwin-send-keys.$CONFIG.keys" 2>"$ERRORS")
  mapfile -t KEYS < <(jq -r '. | keys[]' <<<"$KEYS_JSON" 2>"$ERRORS")
  KEYS_LENGTH=$(jq '. | length' <<<"$KEYS_JSON" 2>"$ERRORS")
  echo "Found key definitions for $CONFIG: $KEYS_LENGTH"
  [ "$KEYS_LENGTH" -lt 1 ] && exit 0
  echo

  filename=""
  mode=""
  owner=""
  postScript=""
  preScript=""
  encSrc=""
  targetDir=""

  for i in $(seq 0 $((KEYS_LENGTH - 1))); do
    echo -n -e "$STATUS Sending key $((i + 1)) of $KEYS_LENGTH: $YELLOW${KEYS[$i]}${NC}... "
    KEY_JSON=$(jq "[.[]] | .[$i]" <<<"$KEYS_JSON" 2>"$ERRORS")
    EXPORT_JSON=$(jq -r '. | to_entries[] | "\(.key)=\"\(.value)\""' <<<"$KEY_JSON" 2>"$ERRORS")

    # Slurp the json data into bash vars
    # shellcheck disable=SC1090
    . <(echo "$EXPORT_JSON")

    # Strip any trailing slash so we don't end up with two in a row which causes an error
    targetDir=${targetDir%/}

    # Do the scripting plus key push
    if [ -n "$preScript" ]; then
      echo -n "Running preScript... "
      ssh "$TARGET" -- /run/current-system/sw/bin/bash -c \'"set -euo pipefail; $preScript"\'
    fi

    echo -n "Pushing and setting ownership and mode... "
    sops -d "$encSrc" |
      ssh "$TARGET" -- /run/current-system/sw/bin/bash \
        -c \'"set -euo pipefail; cat > $targetDir/$filename; chown $owner $targetDir/$filename; chmod $mode $targetDir/$filename"\'

    if [ -n "$postScript" ]; then
      echo -n "Running postScript... "
      ssh "$TARGET" -- /run/current-system/sw/bin/bash -c \'"set -euo pipefail; $postScript"\'
    fi

    echo "Done."
  done

  echo -e "${GREEN}Send keys complete.${NC}"
fi

rm -f "$ERRORS"
exit 0
