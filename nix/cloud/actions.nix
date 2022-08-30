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
      ci = "ci";
      push = "push";
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

        ${factNames.ci}: match: {
          ok: true
          revision: cfg._revision
        }
      }

      output: {
        success: deployed: true
        failure: deployed: false
        [string]: revision: cfg._revision
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
}
