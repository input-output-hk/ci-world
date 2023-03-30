{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (sshKeyLib) allKeysFrom devOps csl-developers remoteBuilderKeys;

  sshKeyLib = import (inputs.ops-lib + "/overlays/ssh-keys.nix") lib;
  sshKeys = allKeysFrom (devOps // {inherit (csl-developers) angerman;});
  extraSshKeys = {
    hydra-queue-runner = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCx2oZoaoHu8YjD94qNp8BfST12FDvgevWloTXqjPQD+diOL1I6nC+nDT2hroAOIkShlM4O2OgbUArmTWc8nPTBUvRClYgjd7jPpVhkyTm9tsHlAFTpgv1n2GPIOK9e97dgU3ZB5phx58WcLVtBeCChFce4EM7oLMKYeo/4pggtal8rtqFjyViPrXncZLtYkIcaKFGBTUMeHi/S3GUiLIlp5VF34L21lPZCy5oZKf70kWWkT52coE4EyEx9fipp2vybMdB/qT4r9pMqa3mmf9IXwfIhoKadpMhPfyaYm+oxmddrSv6aDMjs89fB6cJGpLA5gQFfISQUD1DB8ufjW43v hydra-queue-runner";
  };

  environment =
    lib.concatStringsSep " "
    ["NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];

  authorizedNixStoreKey = key: "command=\"${environment} ${config.nix.package}/bin/nix-store --serve --write\" ${key}";
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
    "per-user/root/ssh/authorized_keys".text =
      lib.concatStringsSep "\n"
      (sshKeys ++ [(authorizedNixStoreKey extraSshKeys.hydra-queue-runner)])
      + "\n";

    "per-user/nixos/ssh/authorized_keys".text =
      lib.concatStringsSep "\n" sshKeys + "\n";
  };

  system.activationScripts.postActivation.text = ''
    printf "configuring ssh keys for hydra on the root account... "
    mkdir -p ~root/.ssh
    cp -f /etc/per-user/root/ssh/authorized_keys ~root/.ssh/authorized_keys
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
}