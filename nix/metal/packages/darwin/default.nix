{
  jq,
  nix,
  sops,
  substituteAll,
  writeShellApplication,
}:
writeShellApplication {
  name = "darwin";
  runtimeInputs = [jq nix sops];
  text = builtins.readFile (substituteAll {
    src = ./darwin.sh;
    parser = builtins.toFile "parser.sh" (builtins.readFile ./parser.sh);
    isExecutable = true;
  });
}
