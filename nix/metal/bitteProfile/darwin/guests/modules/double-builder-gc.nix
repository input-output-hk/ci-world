{
  config,
  lib,
  pkgs,
  ...
}: let
  # To avoid multiple locks on /nix/var/nix/gc.lock and subsequent GC hang,
  # minFreeMB should be significantly higher than nixAutoMinFreeMB.
  # The closer those two numbers are, the more likely GC locking will occur.
  nixAutoMaxFreedMB = 33000; # An absolute amount to free
  nixAutoMinFreeMB = 4000;
  maxFreedMB = 25000; # A relative amount to free
  minFreeMB = 15000;

  cfg = config.nix.builder-gc;
in
  with lib; {
    options = {
      nix.builder-gc.enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Automatically run the garbage collector when free disk space
          falls below a certain level.
        '';
      };

      nix.builder-gc.interval = mkOption {
        type = types.listOf types.attrs;
        default = map (m: {Minute = m;}) [0 15 30 45];
        description = "The time interval at which the garbage collector will run.";
      };

      nix.builder-gc.maxFreedMB = mkOption {
        type = types.int;
        default = maxFreedMB;
        description = ''
          Approximate maximum amount in megabytes to delete.
          This is given as the <filename>nix-collect-garbage --max-freed</filename>
          argument when the garbage collector is run automatically.
        '';
      };

      nix.builder-gc.minFreeMB = mkOption {
        type = types.int;
        default = minFreeMB;
        description = ''
          Low disk level in megabytes which triggers garbage collection.
        '';
      };
    };

    config = {
      nix.extraOptions = ''
        # Try to ensure between ${toString nixAutoMinFreeMB}M and ${toString nixAutoMaxFreedMB}M of free space by
        # automatically triggering a garbage collection if free
        # disk space drops below a certain level during a build.
        min-free = ${toString (nixAutoMinFreeMB * 1048576)}
        max-free = ${toString (nixAutoMaxFreedMB * 1048576)}
      '';

      launchd.daemons.nix-builder-gc = {
        script = ''
          free=$(${pkgs.coreutils}/bin/df --block-size=M --output=avail /nix/store | tail -n1 | sed s/M//)
          echo "Automatic GC: ''${free}M available"
          if [ $free -lt ${toString cfg.minFreeMB} ]; then
            ${config.nix.package}/bin/nix-collect-garbage --max-freed ${toString (cfg.maxFreedMB * 1024 * 1024)}
          fi
        '';
        environment.NIX_REMOTE = lib.optionalString config.services.nix-daemon.enable "daemon";
        serviceConfig.RunAtLoad = false;
        serviceConfig.StartCalendarInterval = cfg.interval;
      };
    };
  }
