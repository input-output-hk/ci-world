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

  services.spongix = {
    enable = true;
    cacheDir = "/var/lib/spongix";
    cacheSize = 400;
    host = "";
    port = 7745;
    gcInterval = "1h";
    secretKeyFiles.ci-world = config.secrets.install.spongix-secret-key.target;
    substituters = ["https://cache.nixos.org" "https://hydra.iohk.io"];
    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      (lib.fileContents (config.secrets.encryptedRoot + "/nix-public-key-file"))
      (lib.fileContents (config.secrets.encryptedRoot + "/spongix-public-key-file"))
    ];
  };

  services.telegraf.overrides.inputs.prometheus = {
    urls = [
      "http://127.0.0.1:${
        toString config.services.promtail.server.http_listen_port
      }/metrics"
      "http://127.0.0.1:${toString config.services.spongix.port}/metrics"
    ];
  };

  systemd.services.spongix-service =
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      service = {
        name = "spongix";
        port = config.services.spongix.port;
        tags = [
          "spongix"
          "ingress"
          "traefik.enable=true"
          "traefik.http.routers.spongix.rule=Host(`cache.ci.iog.io`,`cache.iog.io`) && Method(`GET`, `HEAD`)"
          "traefik.http.routers.spongix.entrypoints=https"
          "traefik.http.routers.spongix.tls=true"
          "traefik.http.routers.spongix.tls.certresolver=acme"
          "traefik.http.routers.spongix-auth.rule=Host(`cache.ci.iog.io`,`cache.iog.io`) && Method(`PUT`, `POST`, `PATCH`)"
          "traefik.http.routers.spongix-auth.entrypoints=https"
          "traefik.http.routers.spongix-auth.tls=true"
          "traefik.http.routers.spongix-auth.tls.certresolver=acme"
          "traefik.http.routers.spongix-auth.middlewares=spongix-auth"
          "traefik.http.middlewares.spongix-auth.digestauth.usersfile=/var/lib/traefik/digest-auth"
          "traefik.http.middlewares.spongix-auth.digestauth.removeheader=true"
        ];

        checks = {
          spongix-tcp = {
            interval = "10s";
            timeout = "5s";
            tcp = "127.0.0.1:${toString config.services.spongix.port}";
          };
        };
      };
    })
    .systemdService;
}
