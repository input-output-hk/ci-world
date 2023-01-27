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
        .packages.${pkgs.system}.cicero-handbook;
    in pkgs.writers.writeDashBin "serve-cicero-handbook" ''
      exec ${lib.getExe pkgs.darkhttpd} ${handbook} --port "$NOMAD_PORT_http"
    '';
  in {
    io = ''
      let push = {
        #lib.io.github_push
        #input: "${factNames.push}"
        #repo: "input-output-hk/cicero"

        // TODO only match default branch when handbook is merged:
        // https://github.com/input-output-hk/cicero/pull/43
        // #default_branch: true
        #branch: "cic-81"
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
          url: "http://${host}"
        }
      }
    '';

    prepare = [{
      type = "nix";
      derivations = map (p: p.drvPath) [entrypoint];
    }];

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
        services = [{
          name = "cicero-handbook";
          port = "http";
          tags = [
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.cicero-handbook.rule=Host(`${host}`) && PathPrefix(`/`)"
          ];
          checks = let
            # one second in nanoseconds
            second = 1000000000;
          in [{
            type = "tcp";
            port = "http";
            interval = 10 * second;
            timeout = 2 * second;
          }];
        }];
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
