{
  inputs,
  cell,
}: let
  inherit (inputs.cicero.packages) webhook-trigger;
  inherit (inputs.nixpkgs) symlinkJoin;
  inherit (inputs.n2c.packages.nix2container) buildImage;
in {
  # jq < result '.layers | map({size: .size, paths: .paths | map(.path)}) | sort_by(.size) | .[11].paths[]' -r | xargs du -sch
  cicero = buildImage (
    cell.library.addN2cNixArgs {
      inherit (cell.entrypoints) cicero;
    } {
      name = "registry.ci.iog.io/cicero";
      tag = "main"; # keep in sync with branch name of flake input
      config.Cmd = ["${cell.entrypoints.cicero}/bin/entrypoint"];
      maxLayers = 60;
      copyToRoot = [
        (symlinkJoin {
          name = "root";
          paths = with inputs.nixpkgs; [
            # for transformers
            jq
            bash
          ];
        })
      ];
    }
  );

  webhook-trigger = buildImage {
    name = "registry.ci.iog.io/webhook-trigger";
    config.Cmd = ["${webhook-trigger}/bin/trigger"];
    maxLayers = 4;
  };
}
