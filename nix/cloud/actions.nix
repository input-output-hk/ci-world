{
  cell,
  inputs,
}: {
  "cicero/cd" = {
    config,
    lib,
    ...
  }: let
    factNames = {
      ci = "CI passed";
      push = "Push to repo";
    };

    newArgs = {
      inputs =
        inputs
        // inputs.std.deSystemize inputs.cicero.packages.default.system {
          cicero = builtins.getFlake "github:input-output-hk/cicero/${config.run.facts.${factNames.ci}.value.revision}";
        };

      cell = cell // {entrypoints = import ./entrypoints newArgs;};
    };

    pushBody = config.run.facts.${factNames.push}.value.github_body;

    branch = lib.removePrefix "refs/heads/" pushBody.ref;
    inherit (pushBody.repository) default_branch;

    jobName = "cicero" + lib.optionalString (branch != default_branch) "-${branch}";

    job =
      builtins.mapAttrs
      (_: job:
        {
          # The job does not explicitely specify the type as it defaults to "service".
          # However, if unset, Cicero sets "batch" as that is more appropriate for most actions.
          # So we explicitely set "service" here to prevent Cicero from changing it to "batch".
          type = "service";
        }
        // job)
      (lib.callPackageWith cell.constants.args.prod ./nomadEnvs/cicero {
        inherit (newArgs) inputs cell;
        inherit branch default_branch;
      })
      .job;
  in {
    io = ''
      let push = {
        #lib.io.github_push
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

    prepare = [
      {
        type = "nix";
        derivations = map (p: p.drvPath) job.${jobName}.group.cicero.task.cicero.config.nix_installables;
      }
    ];

    job = let
      hclFile = __toFile "job.hcl" (builtins.unsafeDiscardStringContext (__toJSON {inherit job;}));
      module = lib.nix-nomad.importNomadModule hclFile {};
    in {
      ${jobName} = args: (module args).job.${jobName};
    };
  };

  "cicero/handbook" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    factNames = {
      ci = "CI passed";
      push = "GitHub Push";
    };

    host = "handbook.cicero.ci.iog.io";

    entrypoint = let
      handbook =
        (builtins.getFlake "github:input-output-hk/cicero/${config.run.facts.${factNames.ci}.value.revision}")
        .packages
        .${pkgs.system}
        .cicero-handbook;
    in
      pkgs.writers.writeDashBin "serve-cicero-handbook" ''
        exec ${lib.getExe pkgs.darkhttpd} ${handbook} --port "$NOMAD_PORT_http"
      '';
  in {
    io = ''
      let push = {
        #lib.io.github_push
        #input: "${factNames.push}"
        #repo: "input-output-hk/cicero"
        #default_branch: true
      }

      inputs: {
        push.inputs

        "${factNames.ci}": match: {
          ok: true
          revision: push._revision
        }
      }

      output: {
        success: "handbook deployed": true
        failure: "handbook deployed": false
        [string]: {
          revision: push._revision
          url: "https://${host}"
        }
      }
    '';

    prepare = [
      {
        type = "nix";
        derivations = map (p: p.drvPath) [entrypoint];
      }
    ];

    job.ciceroHandbook = {
      type = "service";
      namespace = "cicero";
      datacenters = ["eu-central-1"];
      group.handbook = {
        networks = [{port.http = {};}];
        task.handbook = {
          driver = "exec";
          config = {
            command = "/bin/serve-cicero-handbook";
            nix_installables = [entrypoint];
          };
        };
        services = [
          {
            name = "cicero-handbook";
            port = "http";
            tags = [
              "ingress"
              "traefik.enable=true"
              "traefik.http.routers.cicero-handbook.rule=Host(`${host}`) && PathPrefix(`/`)"
              "traefik.http.routers.cicero-handbook.entrypoints=https"
              "traefik.http.routers.cicero-handbook.tls=true"
              "traefik.http.routers.cicero-handbook.tls.certresolver=acme"
            ];
            checks = let
              # one second in nanoseconds
              second = 1000000000;
            in [
              {
                type = "tcp";
                port = "http";
                interval = 10 * second;
                timeout = 2 * second;
              }
            ];
          }
        ];
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
