{
  config,
  lib,
  pkgs,
  ...
}: let
  nixpkgs-unstable = import <nixpkgs-unstable> {};

  # ssh-keys = import ../../lib/ssh-keys.nix lib;

  allowedKeys = [];
  # allowedKeys = ssh-keys.allKeysFrom (ssh-keys.remoteBuilderKeys // ssh-keys.devOps);
  # nix-darwin = (import ../test.nix { host = null; port = null; hostname = null; }).nix-darwin;
in {
  imports = [./double-builder-gc.nix];

  environment.systemPackages = with pkgs;
    [
      nixpkgs-unstable.nix
      tmux
      ncdu
      git
    ]
    ++ (
      if pkgs.stdenv.isDarwin
      then [
        darwin.cctools
      ]
      else []
    );

  time.timeZone = "GMT";

  programs.bash.enable = true;
  programs.zsh.enable = true;

  system.stateVersion = 4;

  nix = {
    package = nixpkgs-unstable.nix;

    extraOptions = ''
      gc-keep-derivations = true
      gc-keep-outputs = true

      # Max of 8 hours for building any given derivation on macOS.
      # The long timeout should give enough time to build a cross GHC.
      # See ../modules/hydra-builder.nix for Linux setting
      timeout = ${toString (3600 * 8)}

      # Quickly kill stuck builds
      max-silent-time = ${toString (60 * 15)}
      sandbox = false
      extra-sandbox-paths = /System/Library/Frameworks /usr/lib /System/Library/PrivateFrameworks
      experimental-features = nix-command flakes
      accept-flake-config = true
    '';

    nixPath = [
      "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
      "darwin-config=/Users/nixos/.nixpkgs/darwin-configuration.nix"
      # "darwin=${nix-darwin}"
    ];

    settings = {
      cores = 0;

      # Match the number of logical cores in your system: sysctl -n hw.ncpu
      max-jobs = 8;

      sandbox = false;
      substituters = ["http://192.168.64.1:8081"];
      trusted-public-keys = [
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
      trusted-users = ["@admin"];
    };
  };

  environment.etc = {
    "per-user/root/ssh/authorized_keys".text = lib.concatStringsSep "\n" allowedKeys + "\n";
    "per-user/nixos/ssh/authorized_keys".text = lib.concatStringsSep "\n" allowedKeys + "\n";
  };

  services.nix-daemon.enable = true;

  launchd.daemons.caffeinate = {
    script = "exec /usr/bin/caffeinate -s";
    serviceConfig.KeepAlive = true;
  };

  system.activationScripts.postActivation.text = ''
    printf "disabling spotlight indexing... "
    mdutil -i off -d / &> /dev/null
    mdutil -E / &> /dev/null
    echo "ok"
    printf "disabling screensaver..."
    defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0
    echo "ok"
    for user in admin nixos buildkite builder; do
        authorized_keys=/etc/per-user/$user/ssh/authorized_keys
        user_home=/Users/$user
        printf "configuring ssh keys for $user... "
        if [ -f $authorized_keys ]; then
            mkdir -p $user_home/.ssh
            cp -f $authorized_keys $user_home/.ssh/authorized_keys
            chown $user: $user_home $user_home/.ssh $user_home/.ssh/authorized_keys
            echo "ok"
        else
            echo "nothing to do"
        fi
    done
  '';
}
