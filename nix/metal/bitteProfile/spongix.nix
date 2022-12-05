{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.spongix.nixosModules.spongix
    inputs.spongix-nar-proxy.nixosModules.nar-proxy
  ];

  systemd.services.spongix.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = lib.mkForce "30s";
    OOMScoreAdjust = 1000;
    MemoryAccounting = "true";
    MemoryMax = "70%";
  };

  services.spongix = {
    enable = true;
    package = inputs.spongix.legacyPackages.x86_64-linux.spongix;
    cacheDir = "/var/lib/spongix";
    host = "";
    port = 7745;
    gc.interval = "daily";
    gc.cacheSize = 400;
    secretKeyFiles.ci-world = config.secrets.install.spongix-secret-key.target;
    substituters = [
      "https://cache.nixos.org"
      "https://iohk-mamba-bitte.s3.eu-central-1.amazonaws.com/infra/binary-cache"
    ];
    trustedPublicKeys = [
      "mamba-testnet-0:bLL+QUo+WSSYJZP5NA9VY97DyIj3YV5US4C6YLHNPGc="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      (lib.fileContents (config.secrets.encryptedRoot + "/nix-public-key-file"))
      (lib.fileContents (config.secrets.encryptedRoot + "/spongix-public-key-file"))
    ];
  };

  services.nar-proxy = {
    enable = true;
    package = inputs.spongix-nar-proxy.legacyPackages.x86_64-linux.spongix;
    cacheUrl = "http://127.0.0.1:${toString config.services.spongix.port}/";
    logLevel = "debug";
  };

  systemd.services.nar-proxy-service =
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      service = {
        name = "nar-proxy";
        port = config.services.nar-proxy.port;
        tags = [
          "nar-proxy"
          "ingress"
          "traefik.enable=true"
          "traefik.http.routers.nar-proxy.rule=Host(`nar-proxy.ci.iog.io`) && Method(`GET`, `HEAD`)"
          "traefik.http.routers.nar-proxy.entrypoints=https"
          "traefik.http.routers.nar-proxy.tls=true"
          "traefik.http.routers.nar-proxy.tls.certresolver=acme"
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

          "traefik.http.routers.spongix-oci.rule=Host(`oci.ci.iog.io`)"
          "traefik.http.routers.spongix-oci.entrypoints=https"
          "traefik.http.routers.spongix-oci.tls=true"
          "traefik.http.routers.spongix-oci.tls.certresolver=acme"
          "traefik.http.routers.spongix-oci.middlewares=spongix-auth"

          "traefik.http.routers.spongix-auth.rule=Host(`cache.ci.iog.io`,`cache.iog.io`) && Method(`PUT`, `POST`, `PATCH`)"
          "traefik.http.routers.spongix-auth.entrypoints=https"
          "traefik.http.routers.spongix-auth.tls=true"
          "traefik.http.routers.spongix-auth.tls.certresolver=acme"
          "traefik.http.routers.spongix-auth.middlewares=spongix-auth"

          "traefik.http.middlewares.spongix-auth.basicauth.usersfile=/var/lib/traefik/basic-auth"
          "traefik.http.middlewares.spongix-auth.basicauth.realm=Spongix"
          "traefik.http.middlewares.spongix-auth.basicauth.removeheader=true"
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
