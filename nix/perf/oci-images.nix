{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs;
  inherit (inputs.bitte-cells) _utils;
  inherit (cell) entrypoints packages healthChecks;
  n2c = inputs.n2c.packages.nix2container;
  buildDebugImage = ep: o: n2c.buildImage (_utils.library.mkDebugOCI ep o);
in {
  postgrest = buildDebugImage entrypoints.postgrest {
    name = "registry.ci.iog.io/postgrest";
    maxLayers = 25;
    layers = [(n2c.buildLayer {deps = [packages.postgrest];})];
    copyToRoot = [nixpkgs.bashInteractive];
    config.Cmd = [
      "${entrypoints.postgrest}/bin/entrypoint"
    ];
    config.User = "1000:1000";
  };
}
