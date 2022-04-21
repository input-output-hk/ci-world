{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) toJSON fromJSON;
in {
  imports = [inputs.spongix.nixosModules.spongix];

  # systemd.tmpfiles.rules = [ "d /mnt/gv0/spongix 1777 root root -" ];

  services.spongix = {
    enable = true;
    cacheDir = "/var/lib/spongix";
    cacheSize = 400;
    host = "";
    port = 7745;
    gcInterval = "1h";
    secretKeyFiles.ci-prod = config.secrets.install.spongix-secret-key.target;
    substituters = ["https://cache.nixos.org" "https://hydra.iohk.io"];
    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      (lib.fileContents (config.secrets.encryptedRoot + "/nix-public-key-file"))
      (lib.fileContents (config.secrets.encryptedRoot + "/spongix-public-key-file"))
    ];
  };

  services.telegraf.extraConfig.inputs.prometheus = {
    urls = [
      "http://127.0.0.1:${
        toString config.services.promtail.server.http_listen_port
      }/metrics"
      "http://127.0.0.1:${toString config.services.spongix.port}/metrics"
    ];
    metric_version = 1;
  };

  systemd.services.spongix-service =
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      service = {
        name = "spongix";
        port = 7745;
        tags = [
          "spongix"
          "ingress"
          "traefik.enable=true"
          "traefik.http.routers.spongix.rule=Host(`cache.ci.iog.io`) || Host(`cache.iog.io`) && Method(`GET`, `HEAD`)"
          "traefik.http.routers.spongix.entrypoints=https"
          "traefik.http.routers.spongix.tls=true"
          "traefik.http.routers.spongix.tls.certresolver=acme"
        ];

        checks = {
          spongix-tcp = {
            interval = "10s";
            timeout = "5s";
            tcp = "127.0.0.1:7745";
          };
        };
      };
    })
    .systemdService;
}
