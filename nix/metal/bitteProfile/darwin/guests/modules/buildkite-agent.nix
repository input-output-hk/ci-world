{
  inputs,
  system,
  config,
  lib,
  pkgs,
  ...
}: let
  nixPkg = inputs.nix.packages.${system}.nix;
  keys = "/Users/nixos/buildkite";
  cfg = config.services.buildkite-services-darwin;
in
  with lib; {
    options = {
      services.buildkite-services-darwin = {
        metadata = mkOption {
          type = types.listOf types.str;
          default = ["system=x86_64-darwin"];
          description = ''
            Metadata associated with a buildkite agent.
          '';
        };

        arch = mkOption {
          type = types.str;
          default = null;
          description = ''
            An architecture string, used to make a disambiguation queue tag.
          '';
        };

        role = mkOption {
          type = types.str;
          default = null;
          description = ''
            A role string, used to make a disambiguation queue tag.
          '';
        };
      };
    };

    config = {
      # On intel, the nix volume appears to not mount quickly enough to not avoid launchdaemon failure.
      # This modification to the default job ensures the job is retried until it succeeds.
      launchd.daemons.buildkite-agent.serviceConfig = {
        RunAtLoad = lib.mkForce null;
        KeepAlive = lib.mkForce true;
        WatchPaths = lib.mkForce null;
      };

      services.buildkite-agent = {
        enable = true;
        package = pkgs.buildkite-agent;
        runtimePackages = with pkgs; [
          bash
          gnutar
          gzip
          bzip2
          xz
          git
          git-lfs
          nixPkg
        ];
        meta-data = lib.concatStringsSep "," cfg.metadata;
        tokenPath = "${keys}/buildkite_token";
        openssh.privateKeyPath = "${keys}/buildkite-ssh-iohk-devops-private";
        openssh.publicKeyPath = "${keys}/buildkite-ssh-iohk-devops-public";
        hooks.pre-command = ''
          creds=${keys}/buildkite_aws_creds
          if [ -e $creds ]; then
            source $creds
          else
            (>&2 echo "$creds doesn't exist. The build is going to fail.")
          fi
        '';
        hooks.environment = ''
          # Provide a minimal build environment
          export NIX_BUILD_SHELL="/run/current-system/sw/bin/bash"
          export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
          # /usr/bin and /usr/sbin are added For iconutil, security, pkgutil, etc.
          # Required for daedalus installer build,
          # or any build which expects to have apple tools.
          export PATH="$PATH:/usr/bin:/usr/sbin"
        '';
        hooks.pre-exit = ''
          echo "Cleaning up the /tmp directory..."

          # Some jobs leave /tmp directories which are not writeable, preventing direct deletion.
          echo "Change moding buildkite agent owned /tmp/* files and directories recursively in preparation for cleanup..."
          find /private/tmp/* -maxdepth 0 -type f,d -user buildkite-agent -print0 | xargs -0 -r chmod -R +w || true

          # Use print0 to handle special filenames and rm -rf to also unlink live and broken symlinks and other special file types.
          echo "Removing buildkite agent owned /tmp/* directories..."
          find /private/tmp/* -maxdepth 0 -type d -user buildkite-agent -print0 | xargs -0 -r rm -rvf || true

          echo "Removing buildkite agent owned /tmp top level files which are not buildkite agent job dependent..."
          find /private/tmp/* -maxdepth 0 -type f \( ! -iname "buildkite-agent*" -and ! -iname "job-env-*" \) -user buildkite-agent -print0 | xargs -0 -r rm -vf || true

          # Avoid prematurely deleting buildkite agent related job files and causing job failures.
          echo "Removing buildkite agent owned /tmp top level files older than 1 day..."
          find /tmp/* -maxdepth 0 -type f -mmin +1440 -user buildkite-agent -print0 | xargs -0 -r rm -vf || true

          echo "Cleanup of /tmp complete."
        '';
        extraConfig = ''
          no-pty=true
          # debug=true
          # priority=9
        '';
        preCommands = ''
          # Only required for a buildkite agent signing role
          source /var/lib/buildkite-agent/signing.sh || true
          /usr/bin/security unlock-keychain -p "$KEYCHAIN" /var/lib/buildkite-agent/ci-signing.keychain-db || true

          # For buildkite access to ioreg utility for unique machine id
          PATH=$PATH:/usr/sbin

          # Ensure networking is available before trying to register as an agent
          until ${pkgs.netcat}/bin/nc -w 1 8.8.8.8 53; do
            echo "Sleeping 10s until internet connectivity is available..."
            sleep 10
          done
        '';
      };

      # this is required to actually create the users -- i don't know why
      users.knownUsers = ["buildkite-agent"];
      users.knownGroups = ["buildkite-agent"];
      users.users.buildkite-agent = {
        uid = 727;
        gid = 727;
      };
      users.groups.buildkite-agent.gid = 727;

      # Fix up group membership and perms on secrets directory.
      # Ensure that buildkite-agent home directory exists with correct
      # permissions. We use applications so this occurs between creating users
      # and launchd scripts
      system.activationScripts.applications.text = ''
        dseditgroup -o edit -a nixos -t user buildkite-agent
        mkdir -p ${keys}
        chgrp -R buildkite-agent ${keys}
        chmod -R o-rx ${keys}

        mkdir -p ${config.users.users.buildkite-agent.home}
        chown buildkite-agent:admin ${config.users.users.buildkite-agent.home}
        chmod 770 ${config.users.users.buildkite-agent.home}
      '';
    };
  }
