{
  config,
  lib,
  pkgs,
  self,
  nodeName,
  etcEncrypted,
  ...
}: let
  cfg = config.services.buildkite-containers;
  ssh-keys = pkgs.ssh-keys;
in
  with lib; {
    imports = [
      # Common host level config (also applied at guest level)
      ./common.nix
      # GC only from the host to avoid duplicating GC in containers
      ./auto-gc.nix
      # Docker module required in both the host and guest containers
      ./docker-builder.nix
    ];

    options = {
      services.buildkite-containers = {
        hostIdSuffix = mkOption {
          type = types.str;
          default = "1";
          description = ''
            A host identifier suffix which is typically a CI server number and is used
            as part of the container name.  Container names are limited to 7 characters,
            so the default naming convention is ci''${hostIdSuffix}-''${containerNum}.
            An example container name, using a hostIdSuffix of 2 for example, may then
            be ci2-4, indicating a 4th CI container on a 2nd host CI server.
          '';
          example = "1";
        };

        queue = mkOption {
          type = types.str;
          default = "default";
          description = ''
            The queue the buildite agent is configured to accept jobs for.
          '';
          example = "1";
        };

        containerList = mkOption {
          type = types.listOf types.attrs;
          default = [
            {
              containerName = "ci${cfg.hostIdSuffix}-1";
              guestIp = "10.254.1.11";
              prio = "9";
              tags.queue = cfg.queue;
            }
            {
              containerName = "ci${cfg.hostIdSuffix}-2";
              guestIp = "10.254.1.12";
              prio = "8";
              tags.queue = cfg.queue;
            }
            {
              containerName = "ci${cfg.hostIdSuffix}-3";
              guestIp = "10.254.1.13";
              prio = "7";
              tags.queue = cfg.queue;
            }
            {
              containerName = "ci${cfg.hostIdSuffix}-4";
              guestIp = "10.254.1.14";
              prio = "6";
              tags.queue = cfg.queue;
            }
          ];
          description = ''
            This parameter allows container customization on a per server basis.
            The default is for 4 buildkite containers.
            Note that container names cannot be more than 7 characters.
          '';
          example = ''
            [ { containerName = "ci1-1"; guestIp = "10.254.1.11"; tags = { system = "x86_64-linux"; queue = "custom"; }; } ];
          '';
        };

        weeklyCachePurge = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to delete the shared /cache dir weekly";
        };

        weeklyCachePurgeOnCalendar = mkOption {
          type = types.str;
          default = "Sat *-*-* 20:00:00";
          description = "The default weekly day and time to perform a weekly /cache dir and swap purge, if enabled.  Uses systemd onCalendar format.";
        };
      };
    };

    config = let
      createBuildkiteContainer = {
        containerName, # The desired container name
        hostIp ? "10.254.1.1", # The IPv4 host virtual eth nic IP
        guestIp ? "10.254.1.11", # The IPv4 container guest virtual eth nic IP
        tags ? {system = "x86_64-linux";}, # Agent metadata customization
        prio ? null, # Agent priority
      }: {
        name = containerName;
        value = {
          autoStart = true;

          bindMounts = {
            "/run/keys" = {
              hostPath = "/run/keys";
            };

            "/var/lib/buildkite-agent/hooks" = {
              hostPath = "/var/lib/buildkite-agent/hooks";
            };

            "/cache" = {
              hostPath = "/cache";
              isReadOnly = false;
            };
          };

          privateNetwork = true;
          hostAddress = hostIp;
          localAddress = guestIp;

          config = {
            imports = [
              # Common guest level config (also applied at host level)
              ./common.nix

              # Prevent nix sandbox related failures
              ./nix_nsswitch.nix

              # Docker module required in both the host and guest containers
              ./docker-builder.nix

              # Ensure the buildkite guests can also generate a nixpkgs link in /run/current-system
              # for legacy nixPath references.
              ({lib, ...}: {
                options = {
                  services.buildkite-containers-guest = {
                    nixpkgs = mkOption {
                      type = types.path;
                      default = self.nixosConfigurations."${config.cluster.name}-${nodeName}".pkgs.path;
                    };
                  };
                };
              })
            ];

            # services.monitoring-exporters.enable = false;

            # Ensure we can use same nixpkgs with overlays the host uses
            nixpkgs.pkgs = pkgs;

            # Don't try to inherit resolved from the equinix host which won't work
            environment.etc."resolv.conf".text = ''
              nameserver 8.8.8.8
            '';

            systemd.services.buildkite-agent-iohk.serviceConfig = {
              ExecStart = mkForce "${pkgs.buildkite-agent}/bin/buildkite-agent start --config /var/lib/buildkite-agent-iohk/buildkite-agent.cfg";
              LimitNOFILE = 1024 * 512;
            };

            services.buildkite-agents.iohk = {
              name = "ci" + "-" + nodeName + "-" + containerName;
              privateSshKeyPath = "/run/keys/buildkite-ssh-iohk-devops-private";
              tokenPath = "/run/keys/buildkite-token";
              inherit tags;
              runtimePackages = with pkgs; [
                bash
                gnutar
                gzip
                bzip2
                xz
                git
                git-lfs
                nix
              ];

              hooks = {
                environment = ''
                  # Provide a minimal build environment
                  export NIX_BUILD_SHELL="/run/current-system/sw/bin/bash"
                  export PATH="/run/current-system/sw/bin:$PATH"

                  # Provide NIX_PATH, unless it's already set by the pipeline
                  if [ -z "''${NIX_PATH:-}" ]; then
                      # see ci-ops/modules/common.nix (system.extraSystemBuilderCmds)
                      export NIX_PATH="nixpkgs=/run/current-system/nixpkgs"
                  fi

                  # load S3 credentials for artifact upload
                  source /var/lib/buildkite-agent/hooks/aws-creds

                  # load extra credentials for user services
                  source /var/lib/buildkite-agent/hooks/buildkite-extra-creds
                '';

                pre-command = ''
                  # Clean out the state that gets messed up and makes builds fail.
                  rm -rf ~/.cabal
                '';

                pre-exit = ''
                  # Clean up the scratch and tmp directories
                  rm -rf /scratch/* &> /dev/null || true
                '';
              };

              extraConfig = ''
                git-clean-flags="-ffdqx"
                ${
                  if prio != null
                  then "priority=${prio}"
                  else ""
                }
              '';
            };

            users.users.buildkite-agent-iohk = {
              isSystemUser = true;
              group = "buildkite-agent-iohk";
              # To ensure buildkite-agent-iohk user sharing of keys in guests
              uid = 10000;
              extraGroups = [
                "keys"
                "docker"
              ];
            };

            users.groups.buildkite-agent-iohk = {
              gid = 10000;
            };

            # Globally enable stack's nix integration so that stack builds have
            # the necessary dependencies available.
            environment.etc."stack/config.yaml".text = ''
              nix:
                enable: true
            '';

            systemd.services.buildkite-agent-custom = {
              wantedBy = ["buildkite-agent-iohk.service"];
              script = ''
                mkdir -p /build /scratch
                chown -R buildkite-agent-iohk:buildkite-agent-iohk /build /scratch
              '';
              serviceConfig = {
                Type = "oneshot";
              };
            };
          };
        };
      };
    in {
      users.users.root.openssh.authorizedKeys.keys = lib.mkForce ssh-keys.ciInfra;

      # Secrets install attr naming is to be consistent within the ci-world repo.
      # Secrets target file naming is to be backwards compatible with the legacy deployment
      # and other scripts which may rely on the legacy naming.
      secrets.install = {
        buildkite-aws-creds = rec {
          source = "${etcEncrypted}/buildkite/buildkite-hook";
          target = "/var/lib/buildkite-agent/hooks/aws-creds";
          outputType = "binary";
          script = ''
            chmod 0770 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # Project-specific credentials to install on Buildkite agents.
        buildkite-extra-creds = rec {
          source = "${etcEncrypted}/buildkite/buildkite-hook-extra-creds.sh";
          target = "/var/lib/buildkite-agent/hooks/buildkite-extra-creds";
          outputType = "binary";
          script = ''
            chmod 0770 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # SSH keypair for buildkite-agent user
        buildkite-ssh-private = rec {
          source = "${etcEncrypted}/buildkite/buildkite-ssh";
          target = "/run/keys/buildkite-ssh-private";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        buildkite-ssh-public = rec {
          source = "${etcEncrypted}/buildkite/buildkite-ssh.pub";
          target = "/run/keys/buildkite-ssh-public";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # SSH keypair for buildkite-agent user (iohk-devops on Github)
        buildkite-ssh-iohk-devops-private = rec {
          source = "${etcEncrypted}/buildkite/buildkite-iohk-devops-ssh";
          target = "/run/keys/buildkite-ssh-iohk-devops-private";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # GitHub deploy key for input-output-hk/hackage.nix
        buildkite-hackage-ssh-private = rec {
          source = "${etcEncrypted}/buildkite/buildkite-hackage-ssh";
          target = "/run/keys/buildkite-hackage-ssh-private";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # GitHub deploy key for input-output-hk/stackage.nix
        buildkite-stackage-ssh-private = rec {
          source = "${etcEncrypted}/buildkite/buildkite-stackage-ssh";
          target = "/run/keys/buildkite-stackage-ssh-private";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # GitHub deploy key for input-output-hk/haskell.nix
        buildkite-haskell-dot-nix-ssh-private = rec {
          source = "${etcEncrypted}/buildkite/buildkite-haskell-dot-nix-ssh";
          target = "/run/keys/buildkite-haskell-dot-nix-ssh-private";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # GitHub deploy key for input-output-hk/cardano-wallet
        buildkite-cardano-wallet-ssh-private = rec {
          source = "${etcEncrypted}/buildkite/buildkite-cardano-wallet-ssh";
          target = "/run/keys/buildkite-cardano-wallet-ssh-private";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # API Token for BuildKite
        buildkite-token = rec {
          source = "${etcEncrypted}/buildkite/buildkite_token";
          target = "/run/keys/buildkite-token";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # DockerHub password/token (base64-encoded in json)
        buildkite-dockerhub-auth = rec {
          source = "${etcEncrypted}/buildkite/dockerhub-auth-config.json";
          target = "/run/keys/dockerhub-auth";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # Catalyst keystore
        buildkite-catalyst-keystore = rec {
          source = "${etcEncrypted}/buildkite/catalyst.keystore";
          target = "/run/keys/catalyst.keystore";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # Catalyst build spec
        buildkite-catalyst-android-build = rec {
          source = "${etcEncrypted}/buildkite/catalyst-android-build.json";
          target = "/run/keys/catalyst-android-build.json";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # Catalyst env vars
        buildkite-catalyst-env = rec {
          source = "${etcEncrypted}/buildkite/catalyst-env.sh";
          target = "/run/keys/catalyst-env.sh";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };

        # Catalyst sentry spec
        buildkite-catalyst-sentry = rec {
          source = "${etcEncrypted}/buildkite/catalyst-sentry.properties";
          target = "/run/keys/catalyst-sentry.properties";
          outputType = "binary";
          script = ''
            chmod 0600 ${target}
            chown buildkite-agent-iohk ${target}
          '';
        };
      };

      system.activationScripts.cacheDir = {
        text = ''
          mkdir -p /cache
          chown -R buildkite-agent-iohk:buildkite-agent-iohk /cache || true
        '';
        deps = [];
      };

      users.users.buildkite-agent-iohk = {
        home = "/var/lib/buildkite-agent";
        isSystemUser = true;
        createHome = true;
        group = "buildkite-agent-iohk";

        # To ensure buildkite-agent-iohk user sharing of keys in guests
        uid = 10000;
      };

      users.groups.buildkite-agent-iohk = {
        gid = 10000;
      };

      environment.etc."mdadm.conf".text = ''
        MAILADDR root
      '';

      environment.systemPackages = [pkgs.nixos-container];

      networking.nat.enable = true;
      networking.nat.internalInterfaces = ["ve-+"];
      networking.nat.externalInterface = "bond0";

      services.fstrim.enable = true;
      services.fstrim.interval = "daily";

      systemd.services.weekly-cache-purge = mkIf cfg.weeklyCachePurge {
        script = ''
          rm -rf /cache/* || true
          ${pkgs.utillinux}/bin/swapoff -a
          ${pkgs.utillinux}/bin/swapon -a
        '';
      };

      systemd.timers.weekly-cache-purge = mkIf cfg.weeklyCachePurge {
        timerConfig = {
          Unit = "weekly-cache-purge.service";
          OnCalendar = cfg.weeklyCachePurgeOnCalendar;
        };
        wantedBy = ["timers.target"];
      };

      containers = builtins.listToAttrs (map createBuildkiteContainer cfg.containerList);
    };
  }
