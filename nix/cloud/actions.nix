{
  cell,
  inputs,
}: {
  "cicero/cd" = {
    task = "cicero/deploy";
    io = ''
      _lib: github: push: #repo: "input-output-hk/cicero"

      inputs: ci: match: {
        ok: true
        revision: inputs."GitHub event".value.github_body.head_commit.id
      }
    '';
  };
}
