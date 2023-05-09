{
  config,
  pkgs,
  ...
}: {
  imports = [./packet.nix];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  system.stateVersion = "22.05";
}
