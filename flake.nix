{
  description = "CI World";
  inputs = {
    std.url = "github:divnix/std";
    n2c.url = "github:nlewo/nix2container";
    data-merge.url = "github:divnix/data-merge";
    flake-arch.url = "github:input-output-hk/flake-arch";
    # --- Bitte Stack ----------------------------------------------
    bitte.url = "github:input-output-hk/bitte/bitte-tests";
    # bitte.url = "path:/home/jlotoski/work/iohk/bitte-wt/bitte-tests";
    # bitte.url = "path:/home/manveru/github/input-output-hk/bitte";
    bitte-cells.url = "github:input-output-hk/bitte-cells";
    # bitte-cells.url = "path:/home/jlotoski/work/iohk/bitte-cells-wt/patroni-metrics";
    bitte.inputs.nomad-driver-nix.follows = "nomad-driver-nix";
    # --------------------------------------------------------------
    # --- Auxiliary Nixpkgs ----------------------------------------
    nixpkgs.follows = "bitte/nixpkgs";
    capsules.url = "github:input-output-hk/devshell-capsules";
    nix-inclusive.url = "github:input-output-hk/nix-inclusive";
    nixpkgs-vector.url = "github:NixOS/nixpkgs/30d3d79b7d3607d56546dd2a6b49e156ba0ec634";
    nomad-driver-nix.url = "github:input-output-hk/nomad-driver-nix";
    spongix.url = "github:input-output-hk/spongix";
    spongix.inputs.cicero.follows = "cicero";
    cicero.url = "github:input-output-hk/cicero";
    cicero.inputs.spongix.follows = "spongix";
    cicero.inputs.driver.follows = "nomad-driver-nix";
    tullia.url = "github:input-output-hk/tullia";
    # --------------------------------------------------------------
  };

  outputs = inputs: let
    inherit (inputs) bitte;
    inherit (inputs.self.x86_64-linux.cloud) nomadEnvs;

    dropAttrs = path: attrsToDrop: attrs:
      inputs.nixpkgs.lib.updateManyAttrsByPath [
        {
          inherit path;
          update = old: builtins.removeAttrs old attrsToDrop;
        }
      ]
      attrs;
    mergeAttrs = newAttrs: attrs: inputs.nixpkgs.lib.recursiveUpdate attrs newAttrs;
  in
    inputs.nixpkgs.lib.pipe (
      (inputs.std.growOn
        {
          inherit inputs;
          inherit (inputs.flake-arch) systems;
          cellsFrom = ./nix;
          # debug = ["cells" "cloud" "nomadEnvs"];
          organelles = [
            (inputs.std.data "nomadEnvs")
            (inputs.std.data "constants")
            (inputs.std.data "alerts")
            (inputs.std.data "dashboards")
            (inputs.std.runnables "entrypoints")
            (inputs.std.functions "bitteProfile")
            (inputs.std.functions "oci-images")
            (inputs.std.functions "library")
            (inputs.std.installables "packages")
            (inputs.std.functions "hydrationProfile")
            (inputs.std.runnables "jobs")
            (inputs.std.devshells "devshells")

            # Tullia
            (inputs.tullia.tasks "pipelines")
            (inputs.std.functions "actions")
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
        }
        (inputs.tullia.fromStd {
          actions = inputs.std.harvest inputs.self ["cloud" "actions"];
          tasks = inputs.std.harvest inputs.self ["automation" "pipelines"];
        })) {
      }
    ) [
      (mergeAttrs {checks.x86_64-linux.devshell-dev = inputs.self.x86_64-linux.automation.devshells.dev;})
      (mergeAttrs {checks.x86_64-linux.devshell-ops = inputs.self.x86_64-linux.automation.devshells.ops;})

      # Drop attrs if needed to address other flake check/arch exclusions
      # (dropAttrs [ ... ] [ ... ])
    ];

  # --- Flake Local Nix Configuration ----------------------------
  nixConfig = {
    extra-substituters = ["https://cache.iog.io"];
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
    # post-build-hook = "./upload-to-cache.sh";
    allow-import-from-derivation = "true";
  };
  # --------------------------------------------------------------
}
