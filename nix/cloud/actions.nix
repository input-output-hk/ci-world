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
    pushInput = "push";
    pushBody = config.run.facts.${pushInput}.value.github_body;
    branch = lib.removePrefix "refs/heads/" pushBody.ref;
  in {
    io = ''
      let cfg = {
        #lib.io.github_push,
        #input: "${pushInput}"
        #repo: "input-output-hk/cicero"
        #default_branch: false
        inputs: _final_inputs
      }

      _final_inputs: inputs
      inputs: {
        cfg.inputs

        ci: match: {
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

    prepare = with cell.oci-images.cicero; [
      {
        type = "nix2container";
        name = "${ociRegistry}/${lib.removePrefix "registry.ci.iog.io/" imageName}:${branch}";
        imageDrv = drvPath;
      }
    ];

    job = let
      inherit (pushBody.repository) default_branch;

      hcl =
        (
          let
            additionalInputs = {cicero = builtins.getFlake "github:input-output-hk/cicero/${pushBody.head_commit.id}";};
            additionalDesystemizedInputs = inputs.std.deSystemize inputs.cicero.defaultPackage.system additionalInputs;
            newInputs = inputs // additionalDesystemizedInputs;
          in
            lib.callPackageWith cell.constants.args.prod ./nomadEnvs/cicero {
              inherit branch default_branch;
              inputs = newInputs;
              cell =
                cell
                // {
                  entrypoints = import ./entrypoints {
                    inherit cell;
                    inputs = newInputs;
                  };
                };
            }
        )
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
