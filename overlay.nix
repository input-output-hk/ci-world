inputs: final: prev: let
  inherit (prev) system;
in {
  inherit (inputs.nomad-driver-nix.packages."${system}") nomad-driver-nix;
  spongix = inputs.spongix.defaultPackage."${system}";
}
