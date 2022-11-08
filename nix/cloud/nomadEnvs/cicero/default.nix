{
  cell,
  inputs,
  namespace,
  domain,
  datacenters ? ["eu-central-1"],
  default_branch ? "main",
  branch ? default_branch,
}: let
  inherit (cell.library) ociNamer;
  inherit (cell) oci-images;
  inherit (inputs.cicero.packages) cicero-entrypoint;
  inherit (inputs.data-merge) merge append;
  inherit (inputs.nixpkgs) writeText lib;

  subdomain =
    lib.optionalString (branch != default_branch) "${branch}."
    + "cicero";

  ciceroName =
    "cicero"
    + lib.optionalString (branch != default_branch) "-${branch}";

  nixConfig = ''
    substituters = http://spongix.service.consul:7745?compression=none
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

  transformers = [
    {
      destination = "/local/transformer-prod.sh";
      perms = "544";
      data = let
        args = {
          # arbitrary revision from nixpkgs-unstable
          nixpkgsRev = "19574af0af3ffaf7c9e359744ed32556f34536bd";
          datacenters = ["eu-central-1"];
          ciceroWebUrl = "https://${subdomain}.${domain}";
          inherit nixConfig postBuildHook;
        };
      in ''
        #! /bin/bash
        /bin/jq --compact-output \
          --argjson args ${lib.escapeShellArg (builtins.toJSON args)} \
          '
            .job |= (
              .Datacenters += $args.datacenters |
              .TaskGroups[]?.Tasks[]? |= (
                .Env |= . + {
                  NOMAD_ADDR: env.NOMAD_ADDR,
                  NOMAD_TOKEN: env.NOMAD_TOKEN,
                  CICERO_WEB_URL: $args.ciceroWebUrl,
                  NIX_CONFIG: ($args.nixConfig + .NIX_CONFIG),
                } |
                .Templates += [{
                  DestPath: "local/post-build-hook",
                  Perms: "544",
                  EmbeddedTmpl: $args.postBuildHook,
                }]
              ) |
              if .Type != null and .Type != "batch" then . else (
                .TaskGroups[]?.Tasks[]? |= (
                  .Vault.Policies += ["cicero"] |
                  if .Driver != "nix" or .Config?.nixos then . else
                    .Config.packages |=
                      # only add bash if needed to avoid conflicts in profile
                      if any(endswith("#bash") or endswith("#bashInteractive"))
                      then .
                      else . + ["github:NixOS/nixpkgs/\($args.nixpkgsRev)#bash"]
                      end
                  end
                )
              ) end
            )
          '
      '';
    }
    {
      destination = "/local/transformer-darwin-nix-remote-builders.sh";
      perms = "544";
      data = let
        templates = [
          {
            # this will be changed to DestPath in the transformer
            DestPathInHome = ".ssh/known_hosts";

            EmbeddedTmpl = let
              builder = i: ''
                {{range (index .Data.data "darwin${toString i}-host" | split "\n") -}}
                10.10.0.${toString i} {{.}}
                {{end}}
              '';
            in ''
              {{with secret "kv/data/cicero/darwin" -}}
              ${builder 1}
              ${builder 2}
              {{end}}
            '';
          }
          {
            DestPath = "\${NOMAD_SECRETS_DIR}/id_buildfarm";
            Perms = "0400";
            EmbeddedTmpl = ''
              {{with secret "kv/data/cicero/darwin"}}{{index .Data.data "buildfarm-private"}}{{end}}
            '';
          }
          {
            DestPath = "\${NOMAD_TASK_DIR}/darwin-nix-remote-builders.env";
            Envvars = true;
            EmbeddedTmpl = let
              builder = i: ''ssh://builder@10.10.0.${toString i} x86_64-darwin /secrets/id_buildfarm 4 2 big-parallel - {{index .Data.data "darwin${toString i}-public" | base64Encode}}'';
            in ''
              {{with secret "kv/data/cicero/darwin"}}
              NIX_CONFIG="builders = ${builder 1} ; ${builder 2}\nbuilders-use-substitutes = true"
              {{end}}
            '';
          }
        ];
      in ''
        #! /bin/bash
        /bin/jq --compact-output \
          --argjson templates ${lib.escapeShellArg (builtins.toJSON templates)} \
          '
            .job.TaskGroups[]?.Tasks[]? |=
              .Env.HOME as $home |
              if $home == null
              then error("`.job.TaskGroups[].Tasks[].Env.HOME` must be set for the darwin-nix-remote-builders transformer")
              else .Templates |= (
                . + (
                  $templates |
                  map(
                    if has("DestPathInHome")
                    then del(.DestPathInHome) + {DestPath: ($home + "/" + .DestPathInHome)}
                    else .
                    end
                  )
                ) |
                unique
              )
              end
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
      driver = "podman";

      config = {
        image = "${oci-images.cicero.imageName}:${branch}";
        force_pull = true;
        command = "${cell.entrypoints.cicero}/bin/entrypoint";
        args = lib.flatten [
          ["--victoriametrics-addr" "http://monitoring.node.consul:8428"]
          ["--prometheus-addr" "http://monitoring.node.consul:3100"]
          ["--transform" (map (t: t.destination) transformers)]
        ];
      };

      vault = {
        policies = ["cicero"];
        change_mode = "restart";
      };

      resources = {
        memory = 1024 * 64;
        cpu = 1000;
      };

      env = {
        NOMAD_ADDR = "https://nomad.${domain}";
        VAULT_ADDR = "https://vault.${domain}";

        NIX_CONFIG = ''
          netrc-file = /secrets/netrc
          sandbox = false # does not work inside podman
          ${nixConfig}
        '';

        # go-getter reads from the NETRC env var or $HOME/.netrc
        # https://github.com/hashicorp/go-getter/blob/4553965d9c4a8d99bd0d381c1180c08e07eff5fd/netrc.go#L24
        NETRC = "/secrets/netrc";

        CICERO_EVALUATOR_NIX_OCI_REGISTRY = "docker://registry.${domain}";
        REGISTRY_AUTH_FILE = "/secrets/docker";
      };

      template =
        transformers
        ++ (let
          data = ''
            machine github.com
            login git
            password {{with secret "kv/data/cicero/github"}}{{.Data.data.token}}{{end}}

            machine api.github.com
            login git
            password {{with secret "kv/data/cicero/github"}}{{.Data.data.token}}{{end}}
          '';
        in [
          {
            destination = "/secrets/netrc";
            inherit data;
          }
          {
            # go-getter's NETRC env var has no effect on the git fetcher.
            # It just invokes git, which invokes curl, which looks for `$HOME/.netrc`.
            destination = "/local/.netrc";
            inherit data;
          }
        ])
        ++ [
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
              DATABASE_URL=postgres://cicero:${pass}@master.${namespace}-database.service.consul/${ciceroName}?target_session_attrs=read-write
            '';
            env = true;
          }

          {
            destination = "/secrets/docker";
            data = ''
              {
                "auths": {
                  "registry.${domain}": {
                    "auth": "{{with secret "kv/data/cicero/docker"}}{{with .Data.data}}{{print .user ":" .password | base64Encode}}{{end}}{{end}}"
                  }
                }
              }
            '';
          }

          {
            destination = "/local/post-build-hook";
            perms = "544";
            data = postBuildHook;
          }

          {
            destination = "/local/env";
            data = ''
              CICERO_EVALUATOR_NIX_EXTRA_ARGS=${builtins.toJSON ''
                  {
                    rootDir = let
                      nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/93950edf017d6a64479069fbf271aa92b7e44d7f";
                      pkgs = nixpkgs.legacyPackages.''
                + "'$'"
                + builtins.toJSON ''
                  {system};
                    in
                      # for transformers
                      pkgs.bash;
                  }
                ''}
            '';
            env = true;
          }
        ];
    };
  };
in {
  job.${ciceroName} = {
    inherit datacenters namespace;

    group.cicero = merge commonGroup {
      service = [
        {
          name = "${ciceroName}-internal";
          address_mode = "auto";
          port = "http";
          tags = [
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.${ciceroName}-internal.rule=Host(`${subdomain}.${domain}`, `${subdomain}.iog.io`) && HeadersRegexp(`Authorization`, `Basic`)"
            "traefik.http.routers.${ciceroName}-internal.middlewares=cicero-auth@consulcatalog"
            "traefik.http.middlewares.cicero-auth.basicauth.users=cicero:$2y$05$lcwzbToms.S83xjBFlHSvO.Lt3Y37b8SLd/9aYuqoSxBOxR9693.2"
            "traefik.http.middlewares.cicero-auth.basicauth.realm=Cicero"
            "traefik.http.routers.${ciceroName}-internal.entrypoints=https"
            "traefik.http.routers.${ciceroName}-internal.tls=true"
            "traefik.http.routers.${ciceroName}-internal.tls.certresolver=acme"
          ];
          canary_tags = [ciceroName];
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
          name = ciceroName;
          address_mode = "auto";
          port = "http";
          tags = [
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.${ciceroName}.rule=Host(`${subdomain}.${domain}`, `${subdomain}.iog.io`)"
            "traefik.http.routers.${ciceroName}.middlewares=oauth-auth-redirect@file"
            "traefik.http.routers.${ciceroName}.entrypoints=https"
            "traefik.http.routers.${ciceroName}.tls=true"
            "traefik.http.routers.${ciceroName}.tls.certresolver=acme"
          ];
          canary_tags = [ciceroName];
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
        args = append ["--web-listen" ":8080"];
      };
    };

    group.cicero-nomad = merge commonGroup {
      count = 2;

      task.cicero.config = {
        args = append ["--" "nomad"];
      };
    };
  };
}
