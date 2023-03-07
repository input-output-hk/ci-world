inputs: final: prev: let
  inherit (prev) system;
  darwinPkgs = inputs.nixpkgs-darwin.legacyPackages.${system};
in {
  spongix = inputs.spongix.defaultPackage.${system};
  utm = darwinPkgs.callPackage ./nix/metal/packages/utm {};
}
