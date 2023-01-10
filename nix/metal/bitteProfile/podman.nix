{
  inputs,
  config,
  lib,
  pkgs,
  dockerAuth,
  ...
}: let
  # Remove and use package from nixpkgs as soon as it includes this PR:
  # https://github.com/hashicorp/nomad-driver-podman/pull/183
  nomad-driver-podman = pkgs.buildGoModule rec {
    pname = "nomad-driver-podman";
    version = "0.4.0";

    src = pkgs.fetchFromGitHub {
      owner = "hashicorp";
      repo = "nomad-driver-podman";
      rev = "2a5da7cba46fbfcbada120515a69dec1f3ff04ad";
      sha256 = "sha256-3KMrgS72s9qkp3Cn0gZzuKnc0wfP8NUfnv1ElI3D3ys=";
    };

    vendorSha256 = "sha256-rGqP7Fzh2zms+GB/XYaoZTnaWQD4GmlJJDYprcH9bZQ=";

    subPackages = ["."];

    # some tests require a running podman service
    doCheck = false;

    meta = with lib; {
      homepage = "https://www.github.com/hashicorp/nomad-driver-podman";
      description = "Podman task driver for Nomad";
      platforms = platforms.linux;
      license = licenses.mpl20;
      maintainers = with maintainers; [manveru];
    };
  };
in {
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

  systemd.services.nomad.path = [nomad-driver-podman];
  systemd.services.nomad.environment.REGISTRY_AUTH_FILE = dockerAuth;

  services.nomad.pluginDir = lib.mkForce (let
    dir = pkgs.symlinkJoin {
      name = "nomad-plugins";
      paths = [
        nomad-driver-podman
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
