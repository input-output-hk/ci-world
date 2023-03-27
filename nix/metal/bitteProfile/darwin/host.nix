darwinName: {
  self,
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
  cachecache = inputs.cachecache.packages.${system}.cachecache;

  guestApply = builtins.toFile "apply.sh" (builtins.readFile ./guests/apply.sh);
  guestConfig = builtins.toFile "darwin-configuration.nix" (builtins.readFile ./guests/darwin-configuration.nix);
in {
  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [
    bittePkgs.utm

    bat
    bottom
    fd
    glances
    gnused # Use expected GNU pattern matching behavior
    gnutar # Apple tar version does not support sparse files
    htop
    icdiff
    jq
    ncdu
    nix-diff
    nix-top
    ripgrep
    screen
    tmux
    tree
    vim
  ];

  programs = {
    bash.enable = true;
    bash.enableCompletion = true;
    zsh.enable = true;
  };

  environment.etc = {
    "per-user/root/ssh/authorized_keys".text = builtins.concatStringsSep "\n" ciInfra;

    "newsyslog.d/org.nixos.cachecache.conf".text = ''
      # logfilename                   [owner:group]  mode  count  size    when  flags  [/pid_file]                    [sig_num]
      /var/log/cachecache.log                        644   10     *       $D0   NJ
    '';

    "newsyslog.d/org.nixos.ncl-ci.conf".text = ''
      # logfilename                   [owner:group]  mode  count  size    when  flags  [/pid_file]                    [sig_num]
      /var/log/ncl-ci.log                            644   10     *       $D0   NJ
    '';

    "newsyslog.d/org.nixos.ncl-signing.conf".text = ''
      # logfilename                   [owner:group]  mode  count  size    when  flags  [/pid_file]                    [sig_num]
      /var/log/ncl-signing.log                       644   10     *       $D0   NJ
    '';
  };

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

    # Ensure required guest files are available for guest bootstrapping
    printf "configuring guest secrets... "
    rm -rf /etc/guests
    mkdir -p /etc/guests/ci/ssh /etc/guests/signing/{ssh,deps} /etc/guests/buildkite
    echo $(hostname -s) > /etc/guests/host-hostname
    cp -Rf ${self}/nix/metal/bitteProfile/darwin/guests/* /etc/guests/

    [ -f /etc/decrypted/guests/netrc ] && cp -f /etc/decrypted/guests/netrc /etc/guests/ || echo "ERROR: Skipping guest netrc token setup: missing"
    [ -d /etc/decrypted/guests/buildkite ] && cp -f /etc/decrypted/guests/buildkite/* /etc/guests/buildkite/ || echo "ERROR: Skipping guest buildkite setup: missing"
    [ -d /etc/decrypted/guests/ci/ssh ] && cp -f /etc/decrypted/guests/ci/ssh/* /etc/guests/ci/ssh/ || echo "ERROR: Skipping guest ci ssh setup: missing"
    [ -d /etc/decrypted/guests/signing/ssh ] && cp -f /etc/decrypted/guests/signing/ssh/* /etc/guests/signing/ssh/ || echo "ERROR: Skipping guest signing ssh setup: missing"
    [ -d /etc/decrypted/guests/signing/deps ] && cp -f /etc/decrypted/guests/signing/deps/* /etc/guests/signing/deps || echo "ERROR: Skipping guest signing deps setup: missing"
    echo "ok"
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

  launchd.daemons = let
    ncl = port:
      pkgs.writeScript "ncl" ''
        #!/bin/sh
        set -euxo pipefail
        ${pkgs.netcat}/bin/nc -dklun ${toString port} | ${pkgs.coreutils}/bin/tr '<' $'\n'
      '';

    mkNetCatLogger = guestService: port: {
      script = ''
        set -euxo pipefail
        ${pkgs.expect}/bin/unbuffer ${ncl port}
      '';

      # See newsyslog drop in above for log rotation
      serviceConfig = {
        KeepAlive = true;
        StandardErrorPath = "/var/log/ncl-${guestService}.log";
        StandardOutPath = "/var/log/ncl-${guestService}.log";
      };
    };
  in {
    cachecache = {
      script = ''
        set -euxo pipefail
        mkdir -p /var/lib/cachecache
        cd /var/lib/cachecache
        ${cachecache}/bin/cachecache
      '';

      # See newsyslog drop in above for log rotation
      serviceConfig = {
        KeepAlive = true;
        StandardErrorPath = "/var/log/cachecache.log";
        StandardOutPath = "/var/log/cachecache.log";
      };
    };

    ncl-ci = mkNetCatLogger "ci" 1514;
    ncl-signing = mkNetCatLogger "signing" 1515;

    caffeinate = {
      script = "exec /usr/bin/caffeinate -s";
      serviceConfig.KeepAlive = true;
    };

    prometheus-node-exporter = {
      script = "exec ${pkgs.prometheus-node-exporter}/bin/node_exporter";

      serviceConfig = {
        KeepAlive = true;
        StandardErrorPath = "/var/log/prometheus-node-exporter.log";
        StandardOutPath = "/var/log/prometheus-node-exporter.log";
      };
    };
  };

  system.stateVersion = 4;
}
