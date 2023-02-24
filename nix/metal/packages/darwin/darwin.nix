{
  nix,
  substituteAll,
  writeShellApplication,
}:
writeShellApplication {
  name = "darwin";
  runtimeInputs = [nix];
  text = builtins.readFile (substituteAll {
    src = ./darwin.sh;
    parser = builtins.toFile "parser.sh" (builtins.readFile ./parser.sh);
    isExecutable = true;
  });
}
