{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (sshKeyLib) allKeysFrom devOps csl-developers;

  sshKeyLib = import (inputs.ops-lib + "/overlays/ssh-keys.nix") lib;
  sshKeys = allKeysFrom (devOps // {inherit (csl-developers) angerman;});
  environment = lib.concatStringsSep " " ["NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];
in {
  imports = [
    ./roles/active-role.nix
    ./arch/active-arch.nix
  ];

  programs.bash.enable = true;
  programs.bash.enableCompletion = false;
  programs.zsh.enable = true;

  services.nix-daemon.enable = true;

  # Guest root ssh keys
  environment.etc = {
    "per-user/root/ssh/authorized_keys".text = lib.concatStringsSep "\n" sshKeys + "\n";
    "per-user/nixos/ssh/authorized_keys".text = lib.concatStringsSep "\n" sshKeys + "\n";
  };

  system.activationScripts.postActivation.text = ''
    # Add a bash prompt to help distinguish host and guest ssh sessions
    /usr/bin/grep -q PS1 /etc/profile || echo 'export PS1="[\\u@\\H \\W \\tZ]\\$ "' >> /etc/profile

    printf "configuring ssh keys on the root account... "
    mkdir -p ~root/.ssh
    cp -f /etc/per-user/root/ssh/authorized_keys ~root/.ssh/authorized_keys
    cat /etc/host-key.pub >> ~root/.ssh/authorized_keys
    chown root:wheel ~root ~root/.ssh ~root/.ssh/authorized_keys
    echo "ok"
  '';

  launchd.daemons.prometheus-node-exporter = {
    # Bind guest node exporter to 9101 instead of default 9100 which the host uses.
    # This will allow requests to both host and guest without conflict under existing pfctl packet routing.
    script = "exec ${pkgs.prometheus-node-exporter}/bin/node_exporter --web.listen-address=:9101";

    serviceConfig = {
      KeepAlive = true;
      StandardErrorPath = "/var/log/prometheus-node-exporter.log";
      StandardOutPath = "/var/log/prometheus-node-exporter.log";
    };
  };

  launchd.daemons.guest-ip-assignment = {
    script = ''
      NAME=$(/bin/hostname -s)
      if [[ $NAME =~ ^.*-ci.*$ ]]; then
        ASSIGNED_IP="192.168.64.2"
      elif [[ $NAME =~ ^.*-signing.*$ ]]; then
        ASSIGNED_IP="192.168.64.3"
      else
        echo "Error: the hostname of this guest needs to have '-ci' or '-signing' in the name."
        exit 1
      fi

      IP=$(/usr/sbin/ipconfig getifaddr en0)

      # Ensure interface en0 is already allocated before trying to take action
      [ "$?" = "0" ] || { echo "$(/bin/date -u): Interface en0 is not yet ip allocated..."; exit 0; }

      # Ensure interface en0 is already UTM bridge allocated on subnet 192.168.64.0/24 before trying to take action
      [[ $IP =~ ^192\.168\.64\..*$ ]] || { echo "$(/bin/date -u): Interface en0 is not yet bridge allocated: $IP..."; exit 0; }

      # Ensure the allocated bridge ip is correct
      if [ "$IP" != "$ASSIGNED_IP" ]; then
        echo "$(/bin/date -u): Updating current ip of $IP to assigned IP of $ASSIGNED_IP"
        ipconfig set en0 INFORM "$ASSIGNED_IP"
      fi
    '';

    serviceConfig = {
      # Run every minute
      StartInterval = 60;
      StandardErrorPath = "/var/log/guest-ip-assignment.log";
      StandardOutPath = "/var/log/guest-ip-assignment.log";
    };
  };
}
