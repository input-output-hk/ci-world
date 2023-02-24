{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs;
in {
  darwin = nixpkgs.callPackage ./darwin/darwin.nix {};
}
