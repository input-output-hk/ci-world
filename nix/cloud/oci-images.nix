{
  inputs,
  cell,
}: let
  inherit (inputs.cicero.packages) cicero-entrypoint cicero webhook-trigger cicero-evaluator-nix;
  inherit (inputs.nixpkgs) symlinkJoin bash jq coreutils curl dig;
  inherit (inputs.n2c.packages.nix2container) buildImage buildLayer;
in {
  # jq < result '.layers | map({size: .size, paths: .paths | map(.path)}) | sort_by(.size) | .[11].paths[]' -r | xargs du -sch
  cicero = buildImage {
    name = "oci.ci.iog.io/cicero";
    config.Cmd = ["${cicero-entrypoint}/bin/entrypoint"];
    maxLayers = 10;
    layers = [
      (buildLayer {deps = [inputs.cicero.packages.cicero];})
      (buildLayer {deps = [inputs.cicero.packages.cicero-evaluator-nix];})
    ];
    contents = [
      (symlinkJoin {
        name = "root";
        paths = [bash jq];
      })
    ];
  };

  webhook-trigger = buildImage {
    name = "oci.ci.iog.io/webhook-trigger";
    config.Cmd = ["${webhook-trigger}/bin/trigger"];
    maxLayers = 4;
  };
}
