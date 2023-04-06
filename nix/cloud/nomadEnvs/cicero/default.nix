{
  cell,
  inputs,
  namespace,
  domain,
  datacenters ? ["eu-central-1"],
  default_branch ? "main",
  branch ? default_branch,
}: let
  inherit (inputs.data-merge) merge append;
  inherit (inputs.nixpkgs) lib runCommand;
  inherit (inputs) nixpkgs;

  subdomain =
    lib.optionalString (branch != default_branch) "${branch}."
    + "cicero";

  ciceroName =
    "cicero"
    + lib.optionalString (branch != default_branch) "-${branch}";

  postBuildHook = nixpkgs.writeShellApplication {
    name = "upload-to-cache";
    text = ''
      set -o noglob
      IFS=' '
      if [[ -v OUT_PATHS ]]; then
        echo "Uploading to cache: $OUT_PATHS"
        #shellcheck disable=SC2086
        exec nix copy --to 'http://spongix.service.consul:7745?compression=none' $OUT_PATHS
      fi
    '';
  };

  # This does not include cache.iog.io because what URL it is available at depends on the environment.
  # This does not include the post-build-hook because its executable path depends on the environment.
  nixConfig = ''
    extra-trusted-public-keys = hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
  '';

  transformers = [
    (nixpkgs.writeShellApplication {
      name = "transform-prod";
      runtimeInputs = with nixpkgs; [jq];
      text = let
        args = {
          datacenters = ["eu-central-1"];
          ciceroWebUrl = "https://${subdomain}.${domain}";
          inherit nixConfig postBuildHook;
          postBuildHookExe = lib.getExe postBuildHook;
          postBuildHookText = ''
            #! /bin/bash
            ${postBuildHook.text}
          '';
        };
        filter = builtins.toFile "filter.jq" ''
          .job |= (
            .Datacenters += $args.datacenters |
            .TaskGroups[]?.Tasks[]? |= (
              .Env |= . + {
                CICERO_WEB_URL: $args.ciceroWebUrl,
                NIX_CONFIG: ($args.nixConfig + "\n" + .NIX_CONFIG),
              } |
              if .Type == null or .Type == "batch" then
                .Vault.Policies += ["cicero"] |

                # Add the post-build-hook.
                if .Driver == "exec" then
                  # As prepare hooks from Cicero's Nix evaluator already ran
                  # this won't cause the post-build-hook to be pushed to the cache.
                  # However, since the Cicero job itself uses the same post-build-hook,
                  # it should already be in the cache.
                  .Config.nix_installables += [$args.postBuildHook] |
                  .Env.NIX_CONFIG += "\npost-build-hook = " + $args.postBuildHookExe
                else
                  .Templates += [{
                    DestPath: "local/post-build-hook",
                    Perms: "544",
                    EmbeddedTmpl: $args.postBuildHookText,
                  }] |
                  .Env.NIX_CONFIG += "\npost-build-hook = /local/post-build-hook"
                end |

                # Add cache.iog.io as the URL it is available at
                # in the respective environment depending on driver settings.
                .Env.NIX_CONFIG += "\n" +
                  if .Driver == "exec" and .Config.nix_host then
                    # The host's Nix daemon only permits the caches it itself trusts.
                    # Make sure the Nix client requests it so that it won't be dropped.
                    "substituters = http://cache:7745"
                  else
                    # The container does not talk to the host's Nix daemon.
                    "substituters = http://spongix.service.consul:7745?compression=none"
                  end
              else . end
            )
          )
        '';
      in ''
        jq --compact-output \
          --from-file ${lib.escapeShellArg filter} \
          --argjson args ${lib.escapeShellArg (builtins.toJSON args)}
      '';
    })
    (nixpkgs.writeShellApplication {
      name = "transform-darwin-nix-remote-builders";
      runtimeInputs = with nixpkgs; [jq];
      text = let
        templates = [
          {
            DestPath = "\${NOMAD_SECRETS_DIR}/id_buildfarm";
            Perms = "0400";
            EmbeddedTmpl = ''
              {{with secret "kv/data/cicero/darwin-ng"}}{{index .Data.data "buildfarm" "private"}}{{end}}
            '';
          }
          {
            DestPathInHome = ".config/nix/nix.conf";
            append = true;

            EmbeddedTmpl = ''
              builders = @/local/home/.config/nix/machines
              builders-use-substitutes = true
            '';
          }
          {
            DestPath = "/local/home/.config/nix/machines";

            EmbeddedTmpl = ''
              {{ with secret "kv/data/cicero/darwin-ng" -}}
              {{ $darwinMachines := .Data.data.darwinMachines -}}
              {{ $publicKeys := .Data.data.publicKeys -}}
              {{ range $m := index .Data.data "activeDarwinMachines" -}}
              {{ index $darwinMachines $m }} {{ index $publicKeys $m | base64Encode }}
              {{ end -}}
              {{ end -}}
            '';
          }
        ];
        templatesJsonBase64 = runCommand "templates.json.base64" {} ''
          printf '%s' ${lib.escapeShellArg (builtins.toJSON templates)} | base64 --wrap 0 - > $out
        '';
        filter = builtins.toFile "filter.jq" ''
          .job.TaskGroups[]?.Tasks[]? |=
            .Env.HOME as $home |
            if $home == null
            then [
              ("darwin-nix-remote-builders: warning: not adding remote darwin nix builders: `.job.TaskGroups[].Tasks[].Env.HOME` must be set\n" | stderr),
              .
            ][1]
            else .Templates |= (
              . + (
                $templates | @base64d | fromjson |
                map(
                  if has("DestPathInHome")
                  then del(.DestPathInHome) + {DestPath: ($home + "/" + .DestPathInHome)}
                  else .
                  end
                )
              ) |
              group_by(.DestPath) |
              map(
                sort_by(.append) |
                if .[length - 1].append | not
                then .
                else [reduce .[range(1; length)] as $tmpl (
                  .[0];
                  if $tmpl | .append | not
                  then error("Multiple templates that are not meant to be appended have the same destination")
                  else . + {EmbeddedTmpl: (.EmbeddedTmpl + "\n" + $tmpl.EmbeddedTmpl)}
                  end
                )]
                end |
                .[] |
                del(.append)
              ) |
              unique
            )
            end
        '';
      in ''
        jq --compact-output \
          --from-file ${lib.escapeShellArg filter} \
          --arg templates ${lib.escapeShellArg (lib.fileContents templatesJsonBase64)}
      '';
    })
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
      driver = "exec";

      config = {
        nix_host = true;
        nix_installables = [cell.entrypoints.cicero postBuildHook] ++ transformers;
        command = lib.getExe cell.entrypoints.cicero;
        args = lib.flatten [
          ["--victoriametrics-addr" "http://monitoring.node.consul:8428"]
          ["--prometheus-addr" "http://monitoring.node.consul:3100"]
          ["--web-cookie-auth" "/secrets/cookie/authentication"]
          ["--web-cookie-enc" "/secrets/cookie/encryption"]
          ["--web-oidc-providers" "/secrets/oidc-providers"]
          ["--transform" (map lib.getExe transformers)]
        ];
      };

      vault = {
        policies = ["cicero"];
        change_mode = "restart";
      };

      resources = {
        memory = 1024 * 16;
        cpu = 1000;
      };

      env = {
        NOMAD_ADDR = "https://nomad.${domain}";
        VAULT_ADDR = "https://vault.${domain}";

        NIX_CONFIG = ''
          netrc-file = /secrets/netrc
          ${nixConfig}
          substituters = http://cache:7745
          post-build-hook = ${lib.getExe postBuildHook}
        '';

        # go-getter reads from the NETRC env var or $HOME/.netrc
        # https://github.com/hashicorp/go-getter/blob/4553965d9c4a8d99bd0d381c1180c08e07eff5fd/netrc.go#L24
        NETRC = "/secrets/netrc";

        CICERO_EVALUATOR_NIX_OCI_REGISTRY = "docker://registry.${domain}";
        CICERO_EVALUATOR_NIX_BINARY_CACHE = "http://spongix.service.consul:7745?compression=none";
        REGISTRY_AUTH_FILE = "/secrets/docker";

        # Required for the transformer that adds darwin nix remote builders.
        HOME = "/local";
      };

      template =
        (let
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
            destination = "/secrets/cookie/authentication";
            data = ''{{(secret "kv/data/cicero/cookie").Data.data.authentication}}'';
          }
          {
            destination = "/secrets/cookie/encryption";
            data = ''{{(secret "kv/data/cicero/cookie").Data.data.encryption}}'';
          }
          {
            destination = "/secrets/oidc-providers";
            data = ''
              {
                "google": {
                  {{with (secret "kv/data/cicero/oauth/google").Data.data -}}
                  "issuer": "https://accounts.google.com",
                  "callback-url": "https://${subdomain}.${domain}/login/oidc/google/callback",
                  "client-id": "{{index . "client-id"}}",
                  "client-secret": "{{index . "client-secret"}}",
                  "auth-query-params": {
                    "access_type": "offline",
                    "prompt": "consent select_account"
                  }
                  {{- end}}
                }
              }
            '';
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
            destination = "/local/env";
            data = ''
              CICERO_EVALUATOR_NIX_EXTRA_ARGS=${builtins.toJSON ''
                  {
                    # XXX Ugly hack to get packages into the image
                    # that are dependencies of scripts added by transformers.
                    # This is only used by tullia for OCI images,
                    # for example when using the podman driver.
                    rootDir = let
                      # arbitrary revision, this one is from nixos-22.11
                      nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/913a47cd064cc06440ea84e5e0452039a85781f0";
                      pkgs = nixpkgs.legacyPackages.''
                + "'$'"
                + builtins.toJSON ''
                  {system};
                    in
                      # for the `postBuildHook`
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
          name = ciceroName;
          address_mode = "auto";
          port = "http";
          tags = [
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.${ciceroName}.rule=Host(`${subdomain}.${domain}`)"
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

      network.port.http = {};

      task.cicero.config.args = append ["--web-listen" ":\${NOMAD_PORT_http}"];
    };

    group.cicero-nomad = merge commonGroup {
      count = 1;

      task.cicero.config.args = append ["--" "nomad"];
    };
  };
}
