{
  cell,
  inputs,
}: {
  "cicero/cd" = {
    task = "cicero/deploy";
    io = ''
      #lib: _

      let cfg = {
        #lib.io.github_push
        #repo: "input-output-hk/cicero"
      }

      inputs: {
        cfg.inputs

        ci: match: {
          ok: true
          revision: output.success.revision
        }
      }

      output: {
        success: deployed: true
        failure: deployed: false
        [Case=string]: revision: cfg.output[Case].revision
      }
    '';
  };
}
