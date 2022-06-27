{
  cell,
  inputs,
  namespace,
  domain,
  datacenters ? ["eu-central-1"],
}: let
  inherit (cell.library) ociNamer;
  inherit (cell) oci-images;
  inherit (inputs.cicero.packages) cicero-entrypoint;
  inherit (inputs.data-merge) merge;
  inherit (inputs.nixpkgs) writeText lib;

  transformers = [
    {
      destination = "/local/transformer-prod.sh";
      perms = "544";
      data = let
        args = {
          # arbitrary revision from nixpkgs-unstable
          nixpkgsRev = "19574af0af3ffaf7c9e359744ed32556f34536bd";
          datacenters = ["eu-central-1"];
          ciceroWebUrl = "https://cicero.ci.iog.io";
          nixConfig = ''
            extra-substituters = http://spongix.service.consul:7745?compression=none
            extra-trusted-public-keys = ci-world-0:fdT/Z5YK5dxaV/kROE4EqaxwTcQSpVpVCSTKuTyIXFY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
            post-build-hook = /local/post-build-hook
          '';
          postBuildHook = ''
            #! /bin/bash
            set -euf
            export IFS=" "
            if [[ -n "$OUT_PATHS" ]]; then
              echo "Uploading to cache: $OUT_PATHS"
              exec nix copy --to "http://spongix.service.consul:7745?compression=none" $OUT_PATHS
            fi
          '';
        };
      in ''
        #! /bin/bash
        /bin/jq --compact-output \
          --argjson args ${lib.escapeShellArg (builtins.toJSON args)} \
          '
            .job[]?.datacenters |= . + $args.datacenters |
            .job[]?.group[]?.task[]? |= (
              .vault.policies |= . + ["cicero"] |
              .env |= . + {
                NOMAD_ADDR: env.NOMAD_ADDR,
                NOMAD_TOKEN: env.NOMAD_TOKEN,
                CICERO_WEB_URL: $args.ciceroWebUrl,
                NIX_CONFIG: ($args.nixConfig + .NIX_CONFIG),
              } |
              .template |= . + [{
                destination: "local/post-build-hook",
                perms: "544",
                data: $args.postBuildHook,
              }] |
              if .driver != "nix" or .config?.nixos then . else
                .config.packages |=
                  # only add bash if needed to avoid conflicts in profile
                  if any(endswith("#bash") or endswith("#bashInteractive"))
                  then .
                  else . + ["github:NixOS/nixpkgs/\($args.nixpkgsRev)#bash"]
                  end
              end
            )
          '
      '';
    }
  ];

  commonGroup = {
    restart = {
      attempts = 5;
      delay = "10s";
      interval = "1m";
      mode = "delay";
    };

    update = {
      canary = 1;
      auto_promote = true;
      auto_revert = true;
    };

    reschedule = {
      delay = "10s";
      delay_function = "exponential";
      max_delay = "1m";
      unlimited = true;
    };

    task.cicero = {
      driver = "docker";

      config = {
        image = ociNamer oci-images.cicero;
        command = "${cell.entrypoints.cicero}/bin/entrypoint";
      };

      vault = {
        policies = ["cicero"];
        change_mode = "restart";
      };

      resources = {
        memory = 4096;
        cpu = 300;
      };

      env = {
        NOMAD_ADDR = "https://nomad.${domain}";
        VAULT_ADDR = "https://vault.${domain}";

        NIX_CONFIG = "netrc-file = /secrets/netrc";

        # go-getter reads from the NETRC env var or $HOME/.netrc
        # https://github.com/hashicorp/go-getter/blob/4553965d9c4a8d99bd0d381c1180c08e07eff5fd/netrc.go#L24
        NETRC = "/secrets/netrc";

        CICERO_EVALUATOR_NIX_OCI_REGISTRY = "docker://registry.ci.iog.io";
        REGISTRY_AUTH_FILE = "/secrets/docker";
      };

      template =
        transformers
        ++ [
          {
            destination = "secrets/netrc";
            data = ''
              machine github.com
              login git
              password {{with secret "kv/data/cicero/github"}}{{.Data.data.token}}{{end}}

              machine api.github.com
              login git
              password {{with secret "kv/data/cicero/github"}}{{.Data.data.token}}{{end}}
            '';
          }

          {
            destination = "/root/.config/git/config";
            data = ''
              [credential]
              	helper = netrc -vkf /secrets/netrc
            '';
          }

          {
            destination = "/secrets/db";
            data = let
              pass = ''{{with secret "kv/data/cicero/db"}}{{.Data.data.value}}{{end}}'';
            in ''
              DATABASE_URL=postgres://cicero:${pass}@master.${namespace}-database.service.consul/cicero?target_session_attrs=read-write
            '';
            env = true;
          }

          {
            destination = "/secrets/docker";
            data = ''{
              "auths": {
                "registry.ci.iog.io": {
                  "auth": "{{with secret "kv/data/cicero/docker"}}{{with .Data.data}}{{print .user ":" .password | base64Encode}}{{end}}{{end}}"
                }
              }
            }'';
          }
        ];
    };
  };
in {
  job.cicero = {
    inherit datacenters namespace;

    group.cicero = merge commonGroup {
      service = [
        {
          name = "cicero-internal";
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
          canary_tags = ["cicero"];
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
          canary_tags = ["cicero"];
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

      network.port.http.to = 8080;

      task.cicero.config = {
        ports = ["http"];
        args = lib.flatten [
          ["--victoriametrics-addr" "http://monitoring.node.consul:8428"]
          ["--prometheus-addr" "http://monitoring.node.consul:3100"]
          ["--web-listen" ":8080"]
          ["--transform" (map (t: t.destination) transformers)]
        ];
      };
    };

    group.cicero-nomad = merge commonGroup {
      count = 3;

      task.cicero.config = {
        args = lib.flatten [
          ["nomad"]
          ["--transform" (map (t: t.destination) transformers)]
        ];
      };
    };
  };
}
