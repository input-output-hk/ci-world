{
  inputs,
  system,
  bittePkgs,
  pkgs,
  ...
}: let
  nixPkg = inputs.nix.packages.${system}.nix;
in {
  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    fd
    glances
    htop
    icdiff
    jq
    nix-diff
    nix-top
    ripgrep
    vim
  ];

  programs = {
    bash.enable = true;
    bash.enableCompletion = true;
    zsh.enable = true;
  };

  system.activationScripts.preActivation.text = ''
    # Ensure ciInfra keys are set up for ssh access
    mkdir -p /var/root/.ssh
    chmod 0700 /var/root/.ssh
    cp ${builtins.toFile "ci-infra-authorized-keys" (builtins.concatStringsSep "\n" bittePkgs.ssh-keys.ciInfra)} /var/root/.ssh/authorized_keys
    chmod 0600 /var/root/.ssh/authorized_keys
  '';

  nix = {
    package = nixPkg;
    gc.automatic = true;
    gc.options = "--max-freed $((10 * 1024 * 1024))";
    gc.user = "root";
    settings = {
      auto-optimise-store = true;
      substituters = ["https://cache.nixos.org" "https://cache.iog.io"];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      ];

      experimental-features = ["nix-command" "flakes" "recursive-nix"];
    };

    registry.nixpkgs = {
      flake = inputs.nixpkgs;
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
    };
  };

  system.stateVersion = 4;
}
