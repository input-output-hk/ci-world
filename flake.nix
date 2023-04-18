{
  description = "CI World";
  inputs = {
    std.url = "github:divnix/std";
    n2c.follows = "std/n2c";
    data-merge.follows = "std/dmerge";
    # --- Bitte Stack ----------------------------------------------
    bitte.url = "github:input-output-hk/bitte";
    bitte-cells.url = "github:input-output-hk/bitte-cells";
    bitte.inputs.nomad-follower.url = "github:input-output-hk/nomad-follower/3ff1d80324a3a716f008fbfc970a0e836c5b34db";
    bitte.inputs.capsules.follows = "capsules";
    # --------------------------------------------------------------
    # --- Auxiliary Nixpkgs ----------------------------------------
    nixpkgs.follows = "bitte/nixpkgs";
    nix.url = "github:NixOS/nix/2.13-maintenance";
    capsules = {
      # Until nixago is implemented, as HEAD currently removes fmt hooks
      url = "github:input-output-hk/devshell-capsules/8dcf0e917848abbe58c58fc5d49069c32cd2f585";

      # To obtain latest available bitte-cli
      inputs.bitte.follows = "bitte";
    };
    nix-inclusive.url = "github:input-output-hk/nix-inclusive";
    nixpkgs-postgrest.url = "github:NixOS/nixpkgs/haskell-updates";
    nixpkgs-vector.url = "github:NixOS/nixpkgs/30d3d79b7d3607d56546dd2a6b49e156ba0ec634";
    spongix.url = "github:input-output-hk/spongix/extract-gc";
    spongix.inputs.cicero.follows = "cicero";
    spongix-nar-proxy.url = "github:input-output-hk/spongix/nar-proxy";
    spongix-nar-proxy.inputs.cicero.follows = "cicero";
    cicero.url = "github:input-output-hk/cicero";
    cicero.inputs.spongix.follows = "spongix";
    tullia.url = "github:input-output-hk/tullia";
    openziti.url = "github:johnalotoski/openziti-bins";
    openziti.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    # --------------------------------------------------------------
    # --- Darwin Specific ------------------------------------------
    # These pins control the darwin hosts
    # For the darwin guests, see: nix/metal/bitteProfile/darwin/guests/flake.nix
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/a3d745e701c337e65ef467d5a9400d9336a303a1";
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-darwin.follows = "nix";
    cachecache.url = "github:cleverca22/cachecache";
    # --------------------------------------------------------------
  };

  outputs = inputs: let
    inherit (inputs) bitte;
    inherit (inputs.self.x86_64-linux.cloud) nomadEnvs;
    inherit (import ./nix/metal/bitteProfile/darwin/lib.nix inputs) mkDarwinConfig;
  in
    (
      inputs.std.growOn
      {
        inherit inputs;
        cellsFrom = ./nix;
        # debug = ["cells" "cloud" "nomadEnvs"];
        cellBlocks = with inputs.std.blockTypes; [
          (data "nomadEnvs")
          (data "constants")
          (data "alerts")
          (data "dashboards")
          (runnables "entrypoints")
          (functions "bitteProfile")
          (containers "oci-images")
          (functions "library")
          (installables "packages")
          (functions "hydrationProfile")
          (runnables "jobs")
          (devshells "devshells")

          # Tullia
          (inputs.tullia.tasks "pipelines")
          (functions "actions")
        ];
      }
      # soil (TODO: eat up soil)
      (
        let
          system = "x86_64-linux";
          overlays = [(import ./overlay.nix inputs)];
        in
          bitte.lib.mkBitteStack {
            inherit inputs;
            inherit (inputs) self;
            inherit overlays;
            domain = "ci.iog.io";
            bitteProfile = inputs.self.${system}.metal.bitteProfile.default;
            hydrationProfile = inputs.self.${system}.cloud.hydrationProfile.default;
            deploySshKey = "./secrets/ssh-ci-world";
          }
      )
      {
        prod = bitte.lib.mkNomadJobs "prod" nomadEnvs;
        perf = bitte.lib.mkNomadJobs "perf" nomadEnvs;
      }
      (inputs.tullia.fromStd {
        actions = inputs.std.harvest inputs.self ["cloud" "actions"];
        tasks = inputs.std.harvest inputs.self ["automation" "pipelines"];
      })
    )
    // {
      darwinConfigurations = {
        # Name = mkDarwinConfig system wgHostAddress extraModules
        mm-intel3 = mkDarwinConfig "mm-intel3" "x86_64-darwin" "10.10.0.3/32" [];
        mm-intel4 = mkDarwinConfig "mm-intel4" "x86_64-darwin" "10.10.0.4/32" [];
        ms-arm1 = mkDarwinConfig "ms-arm1" "aarch64-darwin" "10.10.0.51/32" [];
        ms-arm2 = mkDarwinConfig "ms-arm2" "aarch64-darwin" "10.10.0.52/32" [];
      };
    };

  # --- Flake Local Nix Configuration ----------------------------
  nixConfig = {
    extra-substituters = ["https://cache.iog.io"];
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
    # post-build-hook = "./upload-to-cache.sh";
    allow-import-from-derivation = "true";
  };
  # --------------------------------------------------------------
}
