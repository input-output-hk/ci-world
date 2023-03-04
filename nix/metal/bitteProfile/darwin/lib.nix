inputs: let
  inherit (inputs.nixpkgs) lib;

  bittePkgs = system:
    import inputs.nixpkgs-darwin {
      inherit system;
      overlays = [inputs.bitte.overlays.default];
    };
in {
  mkDarwinConfig = darwinName: system: wgAddresses: extraModules:
    inputs.darwin.lib.darwinSystem {
      inputs = {
        inherit (inputs) darwin openziti;
        nixpkgs = inputs.nixpkgs-darwin;
        nix = inputs.nix-darwin;
      };

      inherit system;
      specialArgs = {
        inherit system;
        bittePkgs = bittePkgs system;
      };

      modules =
        [
          ./host.nix
          (import ./tunnels.nix wgAddresses)
          (import ./send-keys.nix darwinName)
        ]
        ++ lib.optionals (system == "aarch64-darwin") [
          ./aarch64.nix
        ]
        ++ extraModules;
    };
}
