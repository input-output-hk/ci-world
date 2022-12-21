{...}: {
  nix = {
    distributedBuilds = true;
    settings.builders-use-substitutes = true;
    buildMachines = [
      {
        hostName = "builder";
        system = "x86_64-linux";
        maxJobs = 8;
        supportedFeatures = ["benchmark" "big-parallel"];
        protocol = "ssh-ng";
      }
    ];
  };

  programs.ssh.extraConfig = ''
    Host builder
      Hostname 127.0.0.2
      Port 2222
      PubkeyAcceptedKeyTypes ssh-ed25519
      IdentityFile /etc/ssh/ssh_host_ed25519_key
      StrictHostKeyChecking accept-new
      ControlMaster auto
      ControlPath ~/.ssh/master-%r@%n:%p
      ControlPersist 1m
  '';

  boot.enableContainers = true;
  containers = let
    GiB = 1024 * 1024 * 1024;
  in {
    builder = {
      autoStart = true;
      extraFlags = [
        # "--property=MemoryHigh=${toString (1 * GiB)}"
        "--property=MemoryMax=${toString (0.5 * GiB)}"
      ];

      config = {...} @ builder: {
        boot.isContainer = true;
        system.stateVersion = "22.11";
        services.openssh = {
          enable = true;
          ports = [2222];
          startWhenNeeded = true;
        };
        nix = {
          nrBuildUsers = 16;
          gc.automatic = true;
          gc.options = "--max-freed ${toString (10 * GiB)}";
          optimise.automatic = true;
          settings = {
            auto-optimise-store = true;
            cores = 0;
            experimental-features = ["nix-command" "flakes" "recursive-nix" "impure-derivations" "ca-derivations"];
            gc-keep-derivations = true;
            http2 = true;
            keep-outputs = true;
            log-lines = 1000;
            min-free-check-interval = 300;
            sandbox = true;
            show-trace = true;
            tarball-ttl = 60 * 60 * 24 * 30;
            warn-dirty = false;
            trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
            ];
          };
        };
        users = {
          motd = with builder.config; ''
            Welcome to ${networking.hostName}

            - This machine is managed by NixOS
            - All changes are futile

            OS:      NixOS ${system.nixos.release} (${system.nixos.codeName})
            Version: ${system.nixos.version}
            Kernel:  ${boot.kernelPackages.kernel.version}
          '';

          mutableUsers = false;

          users.root = {
            # letmein
            hashedPassword = "$6$EQItH.y3H7pd0Ypi$g/YmYrcxGNzwo3pBDquLGnxTo1bKofJ8OKStsCYsegZb7uBcCiRHCa.JVKpjQ1jGMa2sA6xNPjUotoG7Nrr./0";
            openssh.authorizedKeys.keys = ["FIX_ME"];
          };
        };
      };
    };
  };
}
