{
  pkgs,
  lib,
  config,
  self,
  nodeName,
  ...
}: let
  ssh-keys = pkgs.ssh-keys;
in {
  imports = [
    # ./systemd-exporter.nix
    # ./monitoring-exporters.nix
  ];

  environment.systemPackages = with pkgs; [
    bat
    git
    glances
    graphviz
    htop
    iptables
    jq
    lsof
    ncdu
    sysstat
    sqliteInteractive
    tcpdump
    tig
    tree
    vim
  ];

  environment.variables.TERM = "xterm-256color";

  boot.kernel.sysctl = {
    ## DEVOPS-592
    "kernel.unprivileged_bpf_disabled" = 1;
    "vm.swappiness" = 0;
  };

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = ssh-keys.devOps;

  services = {
    # monitoring-exporters = {
    #   ownIp = config.node.wireguardIP;
    #   useWireguardListeners = true;
    # };
    # nginx.mapHashBucketSize = 128;

    openssh = {
      passwordAuthentication = false;
      authorizedKeysFiles = lib.mkForce ["/etc/ssh/authorized_keys.d/%u"];
      extraConfig = lib.mkOrder 9999 ''
        Match User root
          AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/authorized_keys.d/%u
      '';
    };

    cron.enable = true;
  };

  nix = rec {
    # Use nix sandboxing for greater determinism
    useSandbox = true;

    # Make sure we have enough build users
    nrBuildUsers = 64;

    # If our cache is down, don't wait forever
    extraOptions = ''
      connect-timeout = 10
      http2 = true
      show-trace = true
      experimental-features = nix-command flakes
      allow-import-from-derivation = true
    '';

    # Use all cores
    buildCores = 0;

    nixPath = ["nixpkgs=/run/current-system/nixpkgs"];

    # Use our binary cache builds
    trustedBinaryCaches = ["https://cache.nixos.org" "https://cache.iog.io"];
    binaryCaches = trustedBinaryCaches;
    binaryCachePublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };

  system.extraSystemBuilderCmds =
    if config.services ? "buildkite-containers-guest"
    then ''ln -sv ${config.services.buildkite-containers-guest.nixpkgs} $out/nixpkgs''
    else ''ln -sv ${self.nixosConfigurations."${config.cluster.name}-${nodeName}".pkgs.path} $out/nixpkgs'';
}
