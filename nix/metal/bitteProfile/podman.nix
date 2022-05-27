{
  inputs,
  config,
  lib,
  pkgs,
  dockerAuth,
  ...
}: {
  # Avoid errors due to default overlay driver and zfs systemd execStart opt from showing in cli cmds.
  # Ref: https://github.com/NixOS/nixpkgs/issues/145261#issuecomment-964855713
  virtualisation.containers.storage.settings.storage = {
    driver = "zfs";
    graphroot = "/var/lib/containers/storage";
    runroot = "/run/containers/storage";
  };

  virtualisation.podman = {
    enable = true;
    defaultNetwork.dnsname.enable = true;
  };

  systemd.services.podman.path = [pkgs.zfs];
  systemd.services.podman.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${config.virtualisation.podman.package}/bin/podman --storage-driver zfs $LOGGING system service"
  ];

  networking.firewall.trustedInterfaces = ["podman0"];

  systemd.services.nomad.path = [pkgs.podman];
  systemd.services.nomad.environment.REGISTRY_AUTH_FILE = dockerAuth;

  services.nomad.pluginDir = lib.mkForce (let
    dir = pkgs.symlinkJoin {
      name = "nomad-plugins";
      paths = [
        inputs.nomad-driver-nix.defaultPackage.x86_64-linux
        pkgs.nomad-driver-podman
      ];
    };
  in "${dir}/bin");

  services.nomad.plugin.nomad-driver-podman = {
    socket_path = "unix://run/podman/podman.sock";
    volumes = {
      enabled = true;
      selinuxlabel = "z";
    };
  };
}
