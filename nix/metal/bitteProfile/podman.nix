{
  inputs,
  config,
  lib,
  pkgs,
  dockerAuth,
  ...
}: {
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
