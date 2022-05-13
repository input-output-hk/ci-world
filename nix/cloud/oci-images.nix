{
  inputs,
  cell,
}: let
  inherit (inputs.cicero.packages) cicero-entrypoint webhook-trigger;
  inherit (inputs.nixpkgs) symlinkJoin bash jq coreutils curl dig;
  inherit (inputs.n2c.packages.nix2container) buildImage;
in {
  cicero = buildImage {
    name = "cache.iog.io/cicero";
    config.Cmd = ["/bin/entrypoint"];
    maxLayers = 75;
    contents = [
      (symlinkJoin {
        name = "root";
        paths = [
          (cicero-entrypoint.override {
            gitMinimal = inputs.nixpkgs.gitMinimal.override {
              perlSupport = false;
            };
            bashInteractive = inputs.nixpkgs.bash;
          })
          bash
          jq
        ];
      })
    ];
  };

  webhook-trigger = buildImage {
    name = "cache.iog.io/webhook-trigger";
    config.Cmd = ["${webhook-trigger}/bin/trigger"];
    maxLayers = 4;
  };
}
