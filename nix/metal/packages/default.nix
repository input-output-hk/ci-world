{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs nixpkgs-darwin;
in {
  darwin = nixpkgs.callPackage ./darwin {};
}
