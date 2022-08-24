{
  cell,
  inputs,
}: {
  "cicero/cd" = {
    config,
    lib,
    ociRegistry,
    ...
  }: {
    io = ''
      let cfg = {
        #lib.io.github_push,
        #repo: "input-output-hk/cicero"
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
        name = "${ociRegistry}/${lib.removePrefix "registry.ci.iog.io/" imageName}:${imageTag}";
        imageDrv = drvPath;
      }
    ];

    job.cicero.type = "service";

    imports = [
      (
        let
          hcl =
            (
              (lib.callPackageWith cell.constants.args.prod)
              ./nomadEnvs/cicero
              {
                inherit cell;
                inputs =
                  inputs
                  // {
                    cicero = builtins.getFlake "github:input-output-hk/cicero/${config.preset.github-ci.lib.getRevision "ci" null}";
                  };
              }
            )
            .job;

          hclFile = __toFile "job.hcl" (builtins.unsafeDiscardStringContext (__toJSON {job = hcl;}));
        in
          lib.nix-nomad.importNomadModule hclFile {}
      )
    ];
  };
}
