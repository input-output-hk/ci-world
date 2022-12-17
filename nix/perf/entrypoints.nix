{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs;
  inherit (inputs.bitte-cells._writers.library) writeShellApplication;
  inherit (cell) packages;
in {
  postgrest = writeShellApplication {
    debugInputs = with nixpkgs; [postgresql_12];
    runtimeInputs = [packages.postgrest];
    name = "entrypoint";
    text = ''
      exec postgrest /secrets/postgrest.conf
    '';
  };
}
