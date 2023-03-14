{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../modules/basics.nix
    ../modules/hydra-builder.nix
  ];
}
