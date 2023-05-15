inputs: final: prev: let
  inherit (prev) system;
  darwinPkgs = inputs.nixpkgs-darwin.legacyPackages.${system};
in {
  # Bitte is already pinning nix in the overlay
  nixPkg = inputs.nix.packages.${system}.nix;

  spongix = inputs.spongix.defaultPackage.${system};
  utm = darwinPkgs.callPackage ./nix/metal/packages/utm {};
  auth-keys-hub = inputs.auth-keys-hub.packages.${system}.auth-keys-hub;
}
