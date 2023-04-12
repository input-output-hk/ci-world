#!/bin/bash
set -exo pipefail

LC_TIME=C
echo "Darwin guest bootstrap started at $(date -u)..."

NIX_DARWIN_BOOTSTRAP_URL="https://github.com/LnL7/nix-darwin/archive/master.tar.gz"
PS4='${BASH_SOURCE}::${FUNCNAME[0]}::$LINENO '

HOST_HOSTNAME=$(cat /var/root/share/guests/host-hostname)
HOST_IP="192.168.64.1"

NAME=$(hostname -s)
if [[ $NAME =~ ^.*-ci.*$ ]]; then
  echo "Darwin guest image role is ci..."
  ROLE="ci"
  PORT="1514"
  HOSTNAME="$HOST_HOSTNAME-ci"
elif [[ $NAME =~ ^.*-signing.*$ ]]; then
  echo "Darwin guest image role is signing..."
  ROLE="signing"
  PORT="1515"
  HOSTNAME="$HOST_HOSTNAME-signing"
else
  echo "Error: the hostname from the image needs to have '-ci' or '-signing' in the name for bootstrap role selection."
  exit 1
fi

echo "Redirecting bootstrap script log output to the host udp $HOST_IP:$PORT"
echo "See /var/log/ncl-* on the host for further bootstrap script logs..."
exec 3>&1
exec 2> >(nc -u $HOST_IP $PORT)
exec 1>&2

# Restart the log system with the new syslog config and machine naming
echo "Updating darwin guest logging..."
printf '\n*.*\t@%s:%s\n' "$HOST_IP" "$PORT" >>/etc/syslog.conf
scutil --set HostName "$HOSTNAME"
scutil --set LocalHostName "$HOSTNAME"
scutil --set ComputerName "$HOSTNAME"
dscacheutil -flushcache
pkill syslog || true
pkill asl || true

# Determine the architecture
ARCH=$(arch)
if [ "$ARCH" = "i386" ]; then
  SYSTEM="x86_64-darwin"
elif [ "$ARCH" = "arm64" ]; then
  SYSTEM="aarch64-darwin"
else
  echo "Error: architecture $ARCH is an unrecognized architecture."
  exit 1
fi

if [ -f /etc/.bootstrap-done ]; then
  echo "Darwin guest bootstrap already complete... exiting"
  finish "0"
fi

# The org.nixos.bootup.plist of the pre-bootstrapped image will make sure that
# both intel and arm machines mount guest dependencies to the same location.
#
# Some of the bootstrap activity seems to disrupt the virtiofs driver for arm64 macs,
# making files fail to retreive later on in the script, so we'll grab everything now.
echo "Copying bootstrap files locally..."
mkdir -p /var/root/bootstrap
cp -Rf /var/root/share/guests/* /var/root/bootstrap/
chown -R root:wheel /var/root/bootstrap/
ls -laR /var/root/bootstrap

echo "Preventing darwin guest sleep and unneccessary resource consumption..."
launchctl unload /System/Library/LaunchDaemons/com.apple.metadata.mds.plist
softwareupdate --schedule off
systemsetup -setcomputersleep Never
caffeinate -s &

function finish {
  # Allow finish calls directly with a code or from a trap
  LAST="$?"
  if [ "$#" = "0" ]; then
    RC="$LAST"
  else
    RC="$1"
  fi

  set +e
  cd
  sleep 1
  if [ "$ARCH" = "arm64" ]; then
    umount -f /var/root/share || true
  else
    umount -f /Volumes/share || true
  fi
  rm -rf /var/root/share /var/root/bootstrap

  # Ensure build concurrency is enforced at max-jobs
  # (see modules/basics.nix).
  for i in {5..32}; do dscl . -delete "/Users/_nixbld$i" || true; done
  for i in {5..32}; do dscl . -delete /Groups/nixbld GroupMembership "_nixbld$i" || true; done

  exit "$RC"
}
trap finish EXIT

echo "Setting up darwin guest ssh config..."
cat <<EOF >>/etc/ssh/sshd_config
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
EOF

launchctl stop com.openssh.sshd

cp -rf /var/root/bootstrap/$ROLE/ssh/ssh_host_* /etc/ssh
cp -f /var/root/bootstrap/host-key.pub /etc/
chown root:wheel /etc/ssh/ssh_host_*
chmod 0600 /etc/ssh/ssh_host_*_key
launchctl start com.openssh.sshd
cd /

mkdir -p /etc/sudoers.d
echo "%admin ALL = NOPASSWD: ALL" >/etc/sudoers.d/passwordless

(
  echo
  echo "Installing nix..."
  # Make this thing work as root
  # shellcheck disable=SC2030,SC2031
  export USER=root
  # shellcheck disable=SC2030,SC2031
  export HOME=~root
  env

  # Installing nix will install a system profile nix of this version.
  curl https://releases.nixos.org/nix/nix-2.13.3/install >~nixos/install-nix
  sudo -i -H -u nixos -- sh ~nixos/install-nix --daemon --darwin-use-unencrypted-nix-store-volume </dev/null
)
(
  echo
  echo "Installing nix-darwin..."
  # Make this thing work as root
  # shellcheck disable=SC2030,SC2031
  export USER=root
  # shellcheck disable=SC2030,SC2031
  export HOME=~root

  mkdir -pv /etc/nix
  cat <<EOF >/etc/nix/nix.conf
substituters = http://$HOST_IP:8081
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
experimental-features = nix-command flakes
EOF

  # shellcheck disable=SC1091
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  nix-channel --add https://nixos.org/channels/nixos-22.11 nixpkgs
  nix-channel --add https://nixos.org/channels/nixos-unstable nixpkgs-unstable
  nix-channel --add "$NIX_DARWIN_BOOTSTRAP_URL" darwin
  nix-channel --update

  sudo -i -H -u nixos -- nix-channel --add https://nixos.org/channels/nixos-22.11 nixpkgs
  sudo -i -H -u nixos -- nix-channel --add https://nixos.org/channels/nixos-unstable nixpkgs-unstable
  sudo -i -H -u nixos -- nix-channel --add "$NIX_DARWIN_BOOTSTRAP_URL" darwin
  sudo -i -H -u nixos -- nix-channel --update

  installer=$(nix-build "$NIX_DARWIN_BOOTSTRAP_URL" -A installer --no-out-link)
  set +e
  yes | sudo -i -H -u nixos -- "$installer/bin/darwin-installer"
  echo $?
  sudo launchctl kickstart system/org.nixos.nix-daemon
  set -e
  sleep 10
)
(
  echo
  echo "Preparing for buildkite service..."
  cp -a /var/root/bootstrap/buildkite /Users/nixos/buildkite
  chmod o+rx /Users/nixos
  chmod 0440 /Users/nixos/buildkite/*
)
(
  echo
  echo "Switching into nix-darwin..."

  # shellcheck disable=SC2031
  export USER=root
  # shellcheck disable=SC2031
  export HOME=~root

  # shellcheck disable=SC1091
  . /etc/static/bashrc
  nix profile install nixpkgs#git
  cp -vf /var/root/bootstrap/flake.* ~nixos/.nixpkgs/
  cp -vf /var/root/bootstrap/configuration.nix ~nixos/.nixpkgs/configuration.nix
  cp -vRf /var/root/bootstrap/{modules,roles,arch} ~nixos/.nixpkgs/
  cp -vf /var/root/bootstrap/roles/$ROLE.nix ~nixos/.nixpkgs/roles/active-role.nix
  cp -vf /var/root/bootstrap/arch/$SYSTEM.nix ~nixos/.nixpkgs/arch/active-arch.nix
  sed -i "" -e "s/GUEST/$(hostname -s)/g" -e "s/SYSTEM/$SYSTEM/g" ~nixos/.nixpkgs/flake.nix
  chown -R nixos ~nixos/.nixpkgs
  sudo -iHu nixos -- bash -c 'nix profile install nixpkgs#git; cd .nixpkgs; git init; git add -Av'
  sudo -iHu nixos -- nix build -L ".nixpkgs#darwinConfigurations.$(hostname -s).system"
  sudo -iHu nixos -- result/sw/bin/darwin-rebuild switch --flake .nixpkgs
  rm -f /etc/nix/nix.conf
  cp -vf /var/root/bootstrap/netrc /etc/nix
  chmod 0600 /etc/nix/netrc
  sudo -iHu nixos -- darwin-rebuild switch --flake .nixpkgs

  # Restart the nix-daemon to ensure it is reading the current nix.conf file
  launchctl kickstart -kp system/org.nixos.nix-daemon

  mv /etc/bashrc /etc/bashrc.orig
  mv /etc/zshrc /etc/zshrc.orig
  mv /etc/zprofile /etc/zprofile.orig
  /nix/var/nix/profiles/system/activate

  # Remove the initially installed nix profiles which may version conflict with the nix-darwin config activation
  nix profile remove 0 1 2
  # shellcheck disable=SC1091
  . /etc/profile
  nix doctor
  sudo -iHu nixos -- nix profile remove 0
  rm ~nixos/install-nix
)
(
  if [ "$ROLE" = "signing" ]; then
    set +x
    echo Setting up signing...
    # shellcheck disable=SC1091
    source /var/root/bootstrap/signing/deps/signing.sh
    # shellcheck disable=SC1091
    source /var/root/bootstrap/signing/deps/signing-catalyst.sh
    security create-keychain -p "$KEYCHAIN" ci-signing.keychain
    security default-keychain -s ci-signing.keychain
    security set-keychain-settings ci-signing.keychain
    security list-keychains -d user -s login.keychain ci-signing.keychain
    security unlock-keychain -p "$KEYCHAIN"
    security show-keychain-info ci-signing.keychain
    security import /var/root/bootstrap/signing/deps/iohk-sign.p12 -P "$SIGNING" -k "ci-signing.keychain" -T /usr/bin/productsign
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN" "ci-signing.keychain"
    security import /var/root/bootstrap/signing/deps/iohk-codesign.cer -k /Library/Keychains/System.keychain
    security import /var/root/bootstrap/signing/deps/dev.cer -k /Library/Keychains/System.keychain
    security import /var/root/bootstrap/signing/deps/dist.cer -k /Library/Keychains/System.keychain
    security import /var/root/bootstrap/signing/deps/AppleWWDRCAG3.cer -k /Library/Keychains/System.keychain
    security import /var/root/bootstrap/signing/deps/iohk-codesign.p12 -P "$CODESIGNING" -k /Library/Keychains/System.keychain -T /usr/bin/codesign
    security import /var/root/bootstrap/signing/deps/catalyst-ios-dev.p12 -P "$CATALYST" -k /Library/Keychains/System.keychain -T /usr/bin/codesign
    security import /var/root/bootstrap/signing/deps/catalyst-ios-dist.p12 -P "$CATALYSTDIST" -k /Library/Keychains/System.keychain -T /usr/bin/codesign

    cp /Library/Keychains/ci-signing.keychain /Users/nixos/Library/Keychains/ci-signing.keychain-db
    chown nixos:staff /Users/nixos/Library/Keychains/ci-signing.keychain-db
    mkdir -p /var/lib/buildkite-agent/.private_keys
    cp /Library/Keychains/ci-signing.keychain /var/lib/buildkite-agent/ci-signing.keychain-db
    cp /var/root/bootstrap/signing/deps/signing.sh /var/lib/buildkite-agent/
    cp /var/root/bootstrap/signing/deps/signing-catalyst.sh /var/lib/buildkite-agent/
    cp /var/root/bootstrap/signing/deps/signing-config.json /var/lib/buildkite-agent/
    cp /var/root/bootstrap/signing/deps/code-signing-config.json /var/lib/buildkite-agent/
    cp /var/root/bootstrap/signing/deps/catalyst-ios-build.json /var/lib/buildkite-agent/
    cp /var/root/bootstrap/signing/deps/catalyst-env.sh /var/lib/buildkite-agent/
    cp /var/root/bootstrap/signing/deps/catalyst-sentry.properties /var/lib/buildkite-agent/
    cp "/var/root/bootstrap/signing/deps/AuthKey_${CATALYSTKEY}.p8" "/var/lib/buildkite-agent/.private_keys/AuthKey_${CATALYSTKEY}.p8"
    chown buildkite-agent:admin /var/lib/buildkite-agent/{ci-signing.keychain-db,signing.sh,signing-config.json,code-signing-config.json}
    chown -R buildkite-agent:admin /var/lib/buildkite-agent/{signing-catalyst.sh,catalyst-ios-build.json,catalyst-env.sh,.private_keys}
    chmod 0700 /var/lib/buildkite-agent/.private_keys
    chmod 0400 /var/lib/buildkite-agent/{signing.sh,signing-catalyst.sh} /var/lib/buildkite-agent/.private_keys/*

    export KEYCHAIN
    sudo -Eu nixos -- security unlock-keychain -p "$KEYCHAIN" /Users/nixos/Library/Keychains/ci-signing.keychain-db
    sudo -Eu buildkite-agent -- security unlock-keychain -p "$KEYCHAIN" /var/lib/buildkite-agent/ci-signing.keychain-db
    security unlock-keychain -p "$KEYCHAIN"

    mkdir -p "/var/lib/buildkite-agent/Library/MobileDevice/Provisioning Profiles/"
    mkdir -p /var/lib/buildkite-agent/Library/Developer
    UUID=$(strings /var/root/bootstrap/signing/deps/catalyst-dev.mobileprovision | grep -A1 UUID | tail -n 1 | grep -Eio "[-A-F0-9]{36}")
    cp /var/root/bootstrap/signing/deps/catalyst-dev.mobileprovision "/var/lib/buildkite-agent/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
    UUID=$(strings /var/root/bootstrap/signing/deps/catalyst-dist.mobileprovision | grep -A1 UUID | tail -n 1 | grep -Eio "[-A-F0-9]{36}")
    cp /var/root/bootstrap/signing/deps/catalyst-dist.mobileprovision "/var/lib/buildkite-agent/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
    chown -R buildkite-agent:admin /var/lib/buildkite-agent/Library
    set -x
  fi
)
(
  # Prevent another bootstrap cycle if the same guest is rebooted
  echo "Bootstrap finished successfully."
  launchctl bootout system/org.nixos.bootup
  rm -rf /Library/LaunchDaemons/org.nixos.bootup.plist /var/root/org.nixos.bootup.plist
  touch /etc/.bootstrap-done
  echo "Done."
)
