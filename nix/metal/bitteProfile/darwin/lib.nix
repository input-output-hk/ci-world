inputs: let
  inherit (inputs.nixpkgs) lib;

  bittePkgs = system:
    import inputs.nixpkgs-darwin {
      inherit system;
      overlays = [
        inputs.bitte.overlays.default
        (import ../../../../overlay.nix inputs)
      ];
    };
in {
  mkDarwinConfig = darwinName: system: wgAddresses: extraModules:
    inputs.darwin.lib.darwinSystem {
      inputs = {
        inherit (inputs) darwin cachecache openziti;
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
          (import ./host.nix darwinName)
          (import ./tunnels.nix wgAddresses)
          (import ./send-keys.nix darwinName)
        ]
        ++ lib.optionals (system == "aarch64-darwin") [
          ./aarch64.nix
        ]
        ++ extraModules;
    };
}
