{
  cell,
  inputs,
}: {
  "cicero/cd" = {config, options, lib, ...}: {
    io = ''
      let cfg = {
        #lib.io.github_push
        #repo: "input-output-hk/cicero"
      }

      inputs: {
        cfg.inputs

        ci: match: {
          ok: true

          revision: output.success.revision
          // Declare a direct dependency on the input that has the revision
          // as CUE flows do not consider indirect dependencies.
          _dep: inputs[cfg.#input]
        }
      }

      output: {
        success: deployed: true
        failure: deployed: false
        [Case=string]: revision: cfg.output[Case].revision
      }
    '';

    prepare = [
      rec {
        type = "nix2container";
        name = cell.library.ociNamer imageDrv;
        imageDrv = cell.oci-images.cicero;
      }
    ];

    job.cicero.type = "service";

    imports = [ (
      let
        hcl = (
          (inputs.nixpkgs.lib.callPackageWith cell.constants.args.prod)
          ./nomadEnvs/cicero
          {
            inherit cell;
            inputs = inputs // {
              cicero = builtins.getFlake "github:input-output-hk/cicero/${config.preset.github-ci.lib.getRevision "ci" null}";
            };
          }
        ).job;

        hclFile = __toFile "job.hcl" (builtins.unsafeDiscardStringContext (__toJSON { job = hcl; }));
      in
        lib.nix-nomad.importNomadModule hclFile {}
    ) ];
  };
}
