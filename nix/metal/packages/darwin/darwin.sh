#!/usr/bin/env bash
# Shebang above to satisfy standalone shellcheck outside of writeShellApplication wrapper
# set mode is -euo pipefail by default

# For parsing template updates:
# nix run nixpkgs#argbash -- parser.sh -o parser.sh --strip user-content
# shellcheck disable=SC1091,SC2154
source @parser@

MODE=${_arg_mode:?}
CONFIG=${_arg_config:?}
TARGET=${_arg_target:-}

GREEN='\033[0;32m'
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
  DRV=$(nix path-info --derivation ".#darwinConfigurations.$CONFIG.config.system.build.toplevel" 2>/dev/null)
  echo -e "$STATUS Obtaining nix-darwin derivation system out path for #darwinConfigurations.$CONFIG ..."
  OUT=$(nix-store -q --binding out "$DRV")
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
  echo "TODO"
fi

exit 0
