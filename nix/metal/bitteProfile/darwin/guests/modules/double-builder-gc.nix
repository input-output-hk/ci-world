{
  config,
  lib,
  pkgs,
  ...
}: let
  nixAutoMaxFreedGB = 70; # An absolute amount to free
  nixAutoMinFreeGB = 30;

  # Parameters for the timed GC option
  maxFreedMB = 25000; # A relative amount to free
  minFreeMB = 15000;

  cfg = config.nix.builder-gc;
in
  with lib; {
    options = {
      nix.builder-gc.enableAutoGc = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Automatically run the garbage collector when free disk space
          falls below a certain level.
        '';
      };

      nix.builder-gc.enableTimedGc = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Automatically run the garbage collector on a timed basis.
        '';
      };

      nix.builder-gc.interval = mkOption {
        type = types.listOf types.attrs;
        default = map (m: {Minute = m;}) [0 15 30 45];
        description = "The time interval at which the timed garbage collector will run.";
      };

      nix.builder-gc.maxFreedMB = mkOption {
        type = types.int;
        default = maxFreedMB;
        description = ''
          Approximate maximum amount in megabytes to delete for the timed GC.
          This is given as the <filename>nix-collect-garbage --max-freed</filename>
          argument when the garbage collector is run automatically.
        '';
      };

      nix.builder-gc.minFreeMB = mkOption {
        type = types.int;
        default = minFreeMB;
        description = ''
          Low disk level in megabytes which triggers garbage collection for the timed GC.
        '';
      };
    };

    config = {
      nix.extraOptions = mkIf cfg.enableAutoGc ''
        # Try to ensure between ${toString nixAutoMinFreeGB}GB and ${toString nixAutoMaxFreedGB}GB of free space by
        # automatically triggering a garbage collection if free
        # disk space drops below a certain level during a build.
        min-free = ${toString (nixAutoMinFreeGB * 1024 * 1024 * 1024)}
        max-free = ${toString (nixAutoMaxFreedGB * 1024 * 1024 * 1024)}
      '';

      launchd.daemons.nix-builder-gc = mkIf cfg.enableTimedGc {
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
