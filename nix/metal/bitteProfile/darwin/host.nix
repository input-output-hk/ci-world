{
  inputs,
  system,
  bittePkgs,
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (bittePkgs.ssh-keys) ciInfra buildSlaveKeys;
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

  environment.etc."per-user/root/ssh/authorized_keys".text = builtins.concatStringsSep "\n" ciInfra;

  system.activationScripts.postActivation.text = ''
    # Create a ~/.bashrc containing `source /etc/profile`.
    # Bash doesn't source the ones in /etc for non-interactive
    # shells and that breaks everything nix.
    mkdir -p /Users/builder
    echo "source /etc/profile" > /Users/builder/.bashrc
    chown builder:staff /Users/builder/.bashrc
    dseditgroup -o edit -a builder -t user com.apple.access_ssh

    # Ensure keys are set up for ssh access
    for user in root builder; do
        authorized_keys=/etc/per-user/$user/ssh/authorized_keys

        if [ "$user" = root ]; then
          user_home=/var/root
        else
          user_home=/Users/$user
        fi

        printf "configuring ssh keys for $user... "
        if [ -f $authorized_keys ]; then
            mkdir -p $user_home/.ssh
            cp -f $authorized_keys $user_home/.ssh/authorized_keys
            chown $user: $user_home/.ssh $user_home/.ssh/authorized_keys
            chmod 0700 $user_home/.ssh
            chmod 0600 $user_home/.ssh/authorized_keys
            echo "ok"
        else
            echo "nothing to do"
        fi
    done
  '';

  nix = {
    package = nixPkg;
    gc.automatic = true;
    gc.options = "--max-freed $((10 * 1024 * 1024))";
    gc.user = "root";
    settings = {
      cores = 0;
      max-jobs = "auto";
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

  launchd.daemons.prometheus-node-exporter = {
    script = "exec ${pkgs.prometheus-node-exporter}/bin/node_exporter";
    serviceConfig.KeepAlive = true;
    serviceConfig.StandardErrorPath = "/var/log/prometheus-node-exporter.log";
    serviceConfig.StandardOutPath = "/var/log/prometheus-node-exporter.log";
  };

  system.stateVersion = 4;

  # --- TMP MODS FOR BUILD ON HOST LEVEL

  users.knownUsers = ["builder"];
  users.users.builder = {
    # Start nix-darwin installed users at 1000 (nixos -- reserved), then builder @ 1001
    uid = 1001;

    # Staff
    gid = 20;

    description = "builder";
    home = "/Users/builder";
    shell = "/bin/bash";
  };

  nix.settings.trusted-users = ["root" "builder"];

  environment.etc."per-user/builder/ssh/authorized_keys".text = let
    environment = lib.concatStringsSep " " [
      "NIX_REMOTE=daemon"
      "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
  in
    lib.concatMapStringsSep "\n" (key: ''command="${environment} ${config.nix.package}/bin/nix-store --serve --write" ${key}'') buildSlaveKeys.macos + "\n";
}
