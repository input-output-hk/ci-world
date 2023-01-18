{
  cell,
  inputs,
}: {
  "cicero/cd" = {
    config,
    lib,
    ociRegistry,
    ...
  }: let
    factNames = {
      ci = "CI passed";
      push = "Push to repo";
    };

    newArgs = {
      inputs =
        inputs
        // inputs.std.deSystemize inputs.cicero.defaultPackage.system {
          cicero = builtins.getFlake "github:input-output-hk/cicero/${config.run.facts.${factNames.ci}.value.revision}";
        };

      cell =
        cell
        // {
          oci-images = import ./oci-images.nix newArgs;
          entrypoints = import ./entrypoints newArgs;
        };
    };

    pushBody = config.run.facts.${factNames.push}.value.github_body;

    branch = lib.removePrefix "refs/heads/" pushBody.ref;
  in {
    io = ''
      let push = {
        #lib.io.github_push,
        #input: "${factNames.push}"
        #repo: "input-output-hk/cicero"
      }

      inputs: {
        push.inputs

        "${factNames.ci}": match: {
          ok: true
          revision: push._revision
        }
      }

      output: {
        success: deployed: true
        failure: deployed: false
        [string]: {
          revision: push._revision

          _sub: string
          if push._branch == push._default_branch {
            _sub: ""
          }
          if push._branch != push._default_branch {
            _sub: "\(push._branch)."
          }
          url: "https://\(_sub)cicero.ci.iog.io"
        }
      }
    '';

    prepare = with newArgs.cell.oci-images.cicero; [
      {
        type = "nix2container";
        name = "${ociRegistry}/${lib.removePrefix "registry.ci.iog.io/" imageName}:${branch}";
        imageDrv = drvPath;
      }
    ];

    job = let
      inherit (pushBody.repository) default_branch;

      hcl =
        (lib.callPackageWith cell.constants.args.prod ./nomadEnvs/cicero {
          inherit (newArgs) inputs cell;
          inherit branch default_branch;
        })
        .job;

      hclFile = __toFile "job.hcl" (builtins.unsafeDiscardStringContext (__toJSON {job = hcl;}));

      module = lib.nix-nomad.importNomadModule hclFile {};

      jobName = "cicero" + lib.optionalString (branch != default_branch) "-${branch}";
    in {
      ${jobName} = args:
        (
          __mapAttrs
          (_: job: {type = "service";} // job)
          (module args).job
        )
        .${jobName};
    };
  };

  "cicero/handbook" = {
    config,
    lib,
    ...
  }: let
    factNames = {
      ci = "Deploy Handbook";
      push = "Push to repo";
    };

    handbook = "github:input-output-hk/cicero/${config.run.facts.${factNames.ci}.value.revision}#handbook-entrypoint";
  in {
    io = ''
      let cfg = {
        #lib.io.github_push,
        #input: "${factNames.push}"
        #repo: "input-output-hk/cicero"
        #default_branch: false
        inputs: _final_inputs
      }

      _final_inputs: inputs
      inputs: {
        cfg.inputs

        "${factNames.ci}": match: {
          ok: true
          revision: cfg._revision
        }
      }

      output: {
        success: deployed: true
        failure: deployed: false
        [string]: {
          revision: cfg._revision

          _sub: string
          if cfg._branch == cfg._default_branch {
            _sub: ""
          }
          if cfg._branch != cfg._default_branch {
            _sub: "\(cfg._branch)."
          }
          url: "https://\(_sub)cicero.ci.iog.io"
        }
      }
    '';

    job = {
      ciceroHandbook = {
        namespace = "cicero";
        datacenters = [
          "dc1"
          "eu-central-1"
          "us-east-2"
        ];
        group.handbook = {
          networks = [
            {
              port.http = {};
            }
          ];
          services = [
            {
              name = "cicero-handbook";
              port = "http";
              tags = [
                "ingress"
                "traefik.enable=true"
                "traefik.http.routers.cicero-handbook.rule=Host(`cicero-handbook.ci.iog.io`) && PathPrefix(`/`)"
                "traefik.http.routers.cicero-handbook.entrypoints=https"
                "traefik.http.routers.cicero-handbook.middlewares=oauth-auth-redirect@file"
                "traefik.http.routers.cicero-handbook.tls=true"
                "traefik.http.routers.cicero-handbook.tls.certresolver=acme"
              ];
              checks = [
                {
                  type = "tcp";
                  port = "http";
                  # 10s in nanoseconds
                  interval = 10000000000;
                  # 2s in nanoseconds
                  timeout = 2000000000;
                }
              ];
            }
          ];
          task.handbook = {
            driver = "nix";
            env.HOME = "/local";
            config = {
              packages = [handbook];
              command = ["/bin/serve-cicero-handbook"];
            };
          };
        };
      };
    };
  };

  "ci-world/test-darwin-nix-remote-builders" = rec {
    task = "test-darwin-nix-remote-builders";
    io = ''
      inputs: trigger: match: "ci-world/${task}": "trigger"

      output: {
        success: "x86_64-darwin remote builders work": true
        failure: "x86_64-darwin remote builders work": false
      }
    '';
  };
}
