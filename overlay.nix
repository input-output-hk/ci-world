inputs: final: prev: let
  inherit (prev) system;
in {
  spongix = inputs.spongix.defaultPackage."${system}";
}
