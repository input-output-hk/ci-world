{
  description = "Nix-darwin Guest Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-22.11-darwin";
    nix.url = "github:NixOS/nix/2.15-maintenance";
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
  };

  outputs = inputs: {
    darwinConfigurations.GUEST = inputs.darwin.lib.darwinSystem rec {
      inherit inputs;
      system = "SYSTEM";
      specialArgs = {inherit system;};
      modules = [./configuration.nix];
    };
  };
}
