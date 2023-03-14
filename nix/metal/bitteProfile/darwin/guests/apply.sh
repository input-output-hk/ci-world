#!/bin/bash
set -exo pipefail

NIX_DARWIN_BOOTSTRAP_URL="https://github.com/LnL7/nix-darwin/archive/master.tar.gz"
PS4='${BASH_SOURCE}::${FUNCNAME[0]}::$LINENO '

if [ -f /etc/.bootstrap-done ]; then
  echo "Darwin guest bootstrap already complete... exiting"
  umount -f /var/root/share
  exit 0
else
  echo "Darwin guest bootstrap started at $(date)"
fi

NAME=$(hostname -s)
HOST_HOSTNAME=$(cat /var/root/share/guests/host-hostname)
HOST_IP="192.168.64.1"
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

# Some of the bootstrap activity seems to disrupt the virtiofs driver,
# making files fail to retreive later on in the script, so we'll grab them now.
echo "Copying bootstrap files locally..."
mkdir -p /var/root/bootstrap
cp -a /var/root/share/guests/* /var/root/bootstrap/
chown -R root:wheel /var/root/bootstrap/
ls -laR /var/root/bootstrap

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
pkill syslog
pkill asl

echo "Preventing darwin guest sleep and unneccessary resource consumption..."
launchctl unload /System/Library/LaunchDaemons/com.apple.metadata.mds.plist
softwareupdate --schedule off
systemsetup -setcomputersleep Never
caffeinate -s &

function finish {
  set +e
  cd /
  sleep 1
  umount -f /var/root/share
  # rm -rf /var/root/bootstrap
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
chown root:wheel /etc/ssh/ssh_host_*
chmod 600 /etc/ssh/ssh_host_*
launchctl start com.openssh.sshd
cd /

echo "%admin ALL = NOPASSWD: ALL" >/etc/sudoers.d/passwordless

(
  echo
  echo "Installing nix..."
  # Make this thing work as root
  # shellcheck disable=SC2030,SC2031
  export USER=root
  # shellcheck disable=SC2030,SC2031
  export HOME=~root
  export ALLOW_PREEXISTING_INSTALLATION=1
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
EOF

  # shellcheck disable=SC1091
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  env
  ls -la /private || true
  ls -la /private/var || true
  ls -la /private/var/run || true
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
  sleep 30
)
# (
#     if [ -d /Volumes/CONFIG/buildkite ]
#     then
#       cp -a /Volumes/CONFIG/buildkite /Users/nixos/buildkite
#       pushd /Users/nixos/buildkite
#       mv buildkite-ssh-iohk-devops-public-* buildkite-ssh-iohk-devops-public
#       mv buildkite-ssh-iohk-devops-private-* buildkite-ssh-iohk-devops-private
#       popd
#     fi
# )
(
  echo
  echo "Switching into nix-darwin..."

  # shellcheck disable=SC2031
  export USER=root
  # shellcheck disable=SC2031
  export HOME=~root

  rm -f /etc/bashrc
  ln -s /etc/static/bashrc /etc/bashrc
  # shellcheck disable=SC1091
  . /etc/static/bashrc
  cp -vf /var/root/bootstrap/darwin-configuration.nix ~nixos/.nixpkgs/darwin-configuration.nix
  # cp -vrf /var/root/bootstrap/ci-ops ~nixos/.nixpkgs/ci-ops
  chown -R nixos ~nixos/.nixpkgs
  sudo -iHu nixos -- darwin-rebuild -I /nix/var/nix/profiles/per-user/nixos/channels -I darwin-config=/Users/nixos/.nixpkgs/darwin-configuration.nix build
  rm -f /etc/nix/nix.conf
  # test -f /Volumes/CONFIG/nix/netrc && cp /Volumes/CONFIG/nix/netrc /etc/nix
  sudo -iHu nixos -- darwin-rebuild -I /nix/var/nix/profiles/per-user/nixos/channels -I darwin-config=/Users/nixos/.nixpkgs/darwin-configuration.nix switch

  # Restart the nix-daemon to ensure it is reading the current nix.conf file
  launchctl kickstart -kp system/org.nixos.nix-daemon

  # Remove the initially installed nix profiles which may version conflict with the nix-darwin config activation
  nix profile remove 0 1
  nix doctor
  rm install-nix
)
# (
#     if [ -f /Volumes/CONFIG/signing-config.json ]; then
#         set +x
#         echo Setting up signing...
#         # shellcheck disable=SC1091
#         source /Volumes/CONFIG/signing.sh
#         # shellcheck disable=SC1091
#         source /Volumes/CONFIG/signing-catalyst.sh
#         security create-keychain -p "$KEYCHAIN" ci-signing.keychain
#         security default-keychain -s ci-signing.keychain
#         security set-keychain-settings ci-signing.keychain
#         security list-keychains -d user -s login.keychain ci-signing.keychain
#         security unlock-keychain -p "$KEYCHAIN"
#         security show-keychain-info ci-signing.keychain
#         security import /Volumes/CONFIG/iohk-sign.p12 -P "$SIGNING" -k "ci-signing.keychain" -T /usr/bin/productsign
#         security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN" "ci-signing.keychain"
#         security import /Volumes/CONFIG/iohk-codesign.cer -k /Library/Keychains/System.keychain
#         security import /Volumes/CONFIG/dev.cer -k /Library/Keychains/System.keychain
#         security import /Volumes/CONFIG/dist.cer -k /Library/Keychains/System.keychain
#         security import /Volumes/CONFIG/AppleWWDRCAG3.cer -k /Library/Keychains/System.keychain
#         security import /Volumes/CONFIG/iohk-codesign.p12 -P "$CODESIGNING" -k /Library/Keychains/System.keychain -T /usr/bin/codesign
#         security import /Volumes/CONFIG/catalyst-ios-dev.p12 -P "$CATALYST" -k /Library/Keychains/System.keychain -T /usr/bin/codesign
#         security import /Volumes/CONFIG/catalyst-ios-dist.p12 -P "$CATALYSTDIST" -k /Library/Keychains/System.keychain -T /usr/bin/codesign
#
#
#         cp /private/var/root/Library/Keychains/ci-signing.keychain-db /Users/nixos/Library/Keychains/
#         chown nixos:staff /Users/nixos/Library/Keychains/ci-signing.keychain-db
#         mkdir -p /var/lib/buildkite-agent/.private_keys
#         cp /private/var/root/Library/Keychains/ci-signing.keychain-db /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/signing.sh /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/signing-catalyst.sh /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/signing-config.json /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/code-signing-config.json /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/catalyst-ios-build.json /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/catalyst-env.sh /var/lib/buildkite-agent/
#         cp /Volumes/CONFIG/catalyst-sentry.properties /var/lib/buildkite-agent/
#         cp "/Volumes/CONFIG/AuthKey_${CATALYSTKEY}.p8" "/var/lib/buildkite-agent/.private_keys/AuthKey_${CATALYSTKEY}.p8"
#         chown buildkite-agent:admin /var/lib/buildkite-agent/{ci-signing.keychain-db,signing.sh,signing-config.json,code-signing-config.json}
#         chown -R buildkite-agent:admin /var/lib/buildkite-agent/{signing-catalyst.sh,catalyst-ios-build.json,catalyst-env.sh,.private_keys}
#         chmod 0700 /var/lib/buildkite-agent/.private_keys
#         chmod 0400 /var/lib/buildkite-agent/{signing.sh,signing-catalyst.sh} /var/lib/buildkite-agent/.private_keys/*
#
#         export KEYCHAIN
#         sudo -Eu nixos -- security unlock-keychain -p "$KEYCHAIN" /Users/nixos/Library/Keychains/ci-signing.keychain-db
#         sudo -Eu buildkite-agent -- security unlock-keychain -p "$KEYCHAIN" /var/lib/buildkite-agent/ci-signing.keychain-db
#         security unlock-keychain -p "$KEYCHAIN"
#
#         mkdir -p "/var/lib/buildkite-agent/Library/MobileDevice/Provisioning Profiles/"
#         mkdir -p /var/lib/buildkite-agent/Library/Developer
#         UUID=$(strings /Volumes/CONFIG/catalyst-dev.mobileprovision | grep -A1 UUID | tail -n 1 | egrep -io "[-A-F0-9]{36}")
#         cp /Volumes/CONFIG/catalyst-dev.mobileprovision "/var/lib/buildkite-agent/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
#         UUID=$(strings /Volumes/CONFIG/catalyst-dist.mobileprovision | grep -A1 UUID | tail -n 1 | egrep -io "[-A-F0-9]{36}")
#         cp /Volumes/CONFIG/catalyst-dist.mobileprovision "/var/lib/buildkite-agent/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
#         chown -R buildkite-agent:admin /var/lib/buildkite-agent/Library
#         set -x
#     fi
# )
(
  # Prevent another bootstrap cycle if the same guest is rebooted
  touch /etc/.bootstrap-done
)
