{
  cell,
  inputs,
  namespace,
  domain,
  datacenters ? ["eu-central-1"],
}: let
  inherit (cell.library) ociNamer;
  inherit (cell) oci-images;
  inherit (inputs.nixpkgs) writeText lib;
in {
  job.dev = {
    inherit datacenters namespace;

    group.dev = {
      restart = {
        attempts = 5;
        delay = "10s";
        interval = "1m";
        mode = "delay";
      };

      reschedule = {
        delay = "10s";
        delay_function = "exponential";
        max_delay = "1m";
        unlimited = true;
      };

      network.port.ssh.to = 22;

      task.dev = {
        driver = "docker";

        config = {
          image = ociNamer oci-images.dev;
          command = "/bin/bash";
          ports = ["ssh"];
        };

        env.NIX_CONFIG = ''
          substituters = http://spongix.service.consul:7745?compression=none
          extra-trusted-public-keys = ci-world-0:fdT/Z5YK5dxaV/kROE4EqaxwTcQSpVpVCSTKuTyIXFY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
        '';

        resources = {
          memory = 4096;
          cpu = 3000;
        };
      };

      /*
      service = [
        {
          name = "dev";
          address_mode = "auto";
          port = "http";
          tags = [
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.cicero-internal.rule=Host(`cicero.ci.iog.io`, `cicero.iog.io`) && HeadersRegexp(`Authorization`, `Basic`)"
            "traefik.http.routers.cicero-internal.middlewares=cicero-auth@consulcatalog"
            "traefik.http.middlewares.cicero-auth.basicauth.users=cicero:$2y$05$lcwzbToms.S83xjBFlHSvO.Lt3Y37b8SLd/9aYuqoSxBOxR9693.2"
            "traefik.http.middlewares.cicero-auth.basicauth.realm=Cicero"
            "traefik.http.routers.cicero-internal.entrypoints=https"
            "traefik.http.routers.cicero-internal.tls=true"
            "traefik.http.routers.cicero-internal.tls.certresolver=acme"
          ];
          check = [
            {
              type = "tcp";
              port = "http";
              interval = "10s";
              timeout = "2s";
            }
          ];
        }
        {
          name = "cicero";
          address_mode = "auto";
          port = "http";
          tags = [
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.cicero.rule=Host(`cicero.ci.iog.io`, `cicero.iog.io`)"
            "traefik.http.routers.cicero.middlewares=oauth-auth-redirect@file"
            "traefik.http.routers.cicero.entrypoints=https"
            "traefik.http.routers.cicero.tls=true"
            "traefik.http.routers.cicero.tls.certresolver=acme"
          ];
          check = [
            {
              type = "tcp";
              port = "http";
              interval = "10s";
              timeout = "2s";
            }
          ];
        }
      ];
      */
    };
  };
}
