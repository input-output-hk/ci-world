{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs openziti;
  inherit (inputs.bitte-cells) patroni tempo;
in {
  default = {
    self,
    lib,
    pkgs,
    config,
    terralib,
    bittelib,
    ...
  }: let
    inherit (self.inputs) bitte;
    inherit (config) cluster;
    securityGroupRules = bittelib.securityGroupRules config;
  in {
    secrets.encryptedRoot = ./encrypted;

    cluster = {
      infraType = "awsExt";
      s3CachePubKey = lib.fileContents ./encrypted/nix-public-key-file;
      flakePath = "${inputs.self}";
      vbkBackend = "local";
      builder = "cache";
      transitGateway = {
        enable = true;
        transitRoutes = [
          # Darwin
          {
            gatewayCoreNodeName = "zt";
            cidrRange = "10.10.0.0/24";
          }
          # Equinix, ci-world project
          {
            gatewayCoreNodeName = "zt";
            cidrRange = "10.12.10.0/24";
          }
        ];
      };

      autoscalingGroups = let
        defaultModules = [
          bitte.profiles.client
          bitte.profiles.nomad-follower
          "${self.inputs.nixpkgs}/nixos/modules/profiles/headless.nix"
          ./spongix-user.nix
          ./podman.nix
          ({lib, ...}: {
            services.glusterfs.enable = lib.mkForce false;

            profiles.auxiliaries.builder.remoteBuilder.buildMachine.supportedFeatures = ["big-parallel"];
            virtualisation.containers.ociSeccompBpfHook.enable = true;

            systemd.services.nomad-follower.serviceConfig.LimitNOFILE = "8192";
            systemd.services.nomad.serviceConfig = {
              JobTimeoutSec = "600s";
              JobRunningTimeoutSec = "600s";
            };
          })
        ];

        mkAsgs = region: desiredCapacity: instanceType: volumeSize: node_class: asgSuffix: opts: extraConfig:
          lib.recursiveUpdate
          {
            inherit region desiredCapacity instanceType volumeSize node_class asgSuffix;
            modules =
              defaultModules
              ++ lib.optional (opts ? withPatroni && opts.withPatroni == true) (patroni.nixosProfiles.client node_class)
              ++ lib.optional (node_class == "prod") ({...}: {
                services.nomad.client.host_volume.host-nix-mount = {
                  path = "/nix";
                  read_only = false;
                };
              });
          }
          extraConfig;
        # -------------------------
        # For each list item below which represents an auto-scaler machine(s),
        # an autoscaling group name will be created in the form of:
        #
        #   client-$REGION-$INSTANCE_TYPE
        #
        # This works for most cases, but if there is a use case where
        # machines of the same instance type and region need to be
        # separated into different auto-scaling groups, this can be done by
        # setting a string attribute of `asgSuffix` in the list items needed.
        #
        # If used, asgSuffix must be a string matching a regex of: ^[A-Za-z0-9]$
        # Otherwise, nix will throw an error.
        #
        # Autoscaling groups which utilize an asgSuffix will be named in the form:
        #
        #   client-$REGION-$INSTANCE_TYPE-$ASG_SUFFIX
      in
        lib.listToAttrs (lib.forEach [
            (mkAsgs "eu-central-1" 7 "m5.8xlarge" 500 "prod" "prod" {withPatroni = true;} {})
            (mkAsgs "eu-central-1" 0 "m5.metal" 1000 "baremetal" "baremetal" {} {primaryInterface = "enp125s0";})
            (mkAsgs "eu-central-1" 1 "t3a.medium" 100 "test" "test" {} {})
          ]
          (args: let
            attrs =
              {
                desiredCapacity = 1;
                instanceType = "t3a.large";
                associatePublicIP = true;
                maxInstanceLifetime = 0;
                iam.role = cluster.iam.roles.client;
                iam.instanceProfile.role = cluster.iam.roles.client;

                securityGroupRules = {
                  inherit (securityGroupRules) internet internal ssh;
                };
              }
              // args;
            attrs' = removeAttrs attrs ["asgSuffix"];
            suffix =
              if args ? asgSuffix
              then
                if (builtins.match "^[A-Za-z0-9]+$" args.asgSuffix) != null
                then "-${args.asgSuffix}"
                else throw "asgSuffix must regex match a string of ^[A-Za-z0-9]$"
              else "";
            asgName = "client-${attrs.region}-${
              builtins.replaceStrings ["."] ["-"] attrs.instanceType
            }${suffix}";
          in
            lib.nameValuePair asgName attrs'));

      instances = {
        core-1 = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.0.10";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 100;

          modules = [
            bitte.profiles.core
            bitte.profiles.bootstrapper
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        core-2 = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.1.10";
          subnet = cluster.vpc.subnets.core-2;
          volumeSize = 100;

          modules = [
            bitte.profiles.core
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        core-3 = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.2.10";
          subnet = cluster.vpc.subnets.core-3;
          volumeSize = 100;

          modules = [
            bitte.profiles.core
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        monitoring = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.0.20";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 300;

          modules = [
            bitte.profiles.monitoring
            ({lib, ...}: {
              # If this is needed, check there isn't a rogue logger first
              # services.loki.configuration.limits_config = {
              #   per_stream_rate_limit = "10MB";
              #   per_stream_rate_limit_burst = "30MB";
              # };

              services.prometheus.exporters.blackbox = lib.mkForce {
                enable = true;
                configFile = pkgs.toPrettyJSON "blackbox-exporter.yaml" {
                  modules = {
                    ssh_banner = {
                      prober = "tcp";
                      timeout = "10s";
                      tcp = {
                        preferred_ip_protocol = "ip4";
                        query_response = [
                          {
                            expect = "^SSH-2.0-";
                            send = "SSH-2.0-blackbox-ssh-check";
                          }
                        ];
                      };
                    };
                  };
                };
              };

              services.vmagent.promscrapeConfig = let
                mkTarget = ip: machine: {
                  targets = ["${ip}:22"];
                  labels.alias = machine;
                };
              in [
                {
                  job_name = "blackbox-ssh-darwin";
                  scrape_interval = "60s";
                  metrics_path = "/probe";
                  params.module = ["ssh_banner"];
                  static_configs = [
                    (mkTarget "10.10.0.1" "mm1-builder")
                    (mkTarget "10.10.0.2" "mm2-builder")
                    (mkTarget "10.10.0.101" "mm1-signer")
                    (mkTarget "10.10.0.102" "mm2-signer")
                  ];
                  relabel_configs = [
                    {
                      source_labels = ["__address__"];
                      target_label = "__param_target";
                    }
                    {
                      source_labels = ["__param_target"];
                      target_label = "instance";
                    }
                    {
                      replacement = "127.0.0.1:9115";
                      target_label = "__address__";
                    }
                  ];
                }
              ];
            })
          ];

          securityGroupRules = {
            inherit
              (securityGroupRules)
              internet
              internal
              ssh
              http
              https
              ;
          };
        };

        routing = {
          instanceType = "t3a.small";
          privateIP = "172.16.1.20";
          subnet = cluster.vpc.subnets.core-2;
          volumeSize = 100;
          route53.domains = ["*.${cluster.domain}"];

          modules = [
            bitte.profiles.routing

            # Required temporarily because bitte-cells.tempo.hydrationProfile qualifies
            # routing machine nixosProfile inclusion on infraType = "aws", and this is
            # an infraType "awsExt" cluster.
            #
            # TODO: update bitte-cells to include awsExt, plus other bitte-cells
            tempo.nixosProfiles.routing

            ({
              etcEncrypted,
              config,
              ...
            }: {
              services.traefik = {
                # Enables cert management via job tabs vs extraSANs
                acmeDnsCertMgr = false;

                # Changing to default of false soon
                useDockerRegistry = false;

                # Changing to a default of true soon
                useVaultBackend = true;

                staticConfigOptions = {
                  entryPoints = {
                    http = lib.mkForce {
                      address = ":80";
                      forwardedHeaders.insecure = true;
                    };

                    https = {
                      address = ":443";
                      forwardedHeaders.insecure = true;
                    };

                    metrics = {
                      address = "127.0.0.1:${toString config.services.traefik.prometheusPort}";
                    };
                  };
                };
              };

              # For spongix basic auth
              secrets.install.basicAuth = {
                inputType = "binary";
                outputType = "binary";
                source = "${etcEncrypted}/basic-auth";
                target = /var/lib/traefik/basic-auth;
                script = ''
                  chown traefik:traefik /var/lib/traefik/basic-auth
                  chmod 0600 /var/lib/traefik/basic-auth
                '';
              };
            })
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh http https routing;
          };
        };

        cache = {
          instanceType = "m5.4xlarge";
          privateIP = "172.16.0.52";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 2000;

          modules = [
            (bitte + /profiles/auxiliaries/telegraf.nix)
            (bitte + /modules/docker-registry.nix)
            ./cache.nix
            ./spongix-user.nix
            {services.docker-registry.enable = true;}
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        zt = {
          # https://support.netfoundry.io/hc/en-us/articles/360025875331-Edge-Router-VM-Sizing-Guide
          instanceType = "c5.large";
          privateIP = "172.16.0.30";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 100;
          route53.domains = ["zt.${cluster.domain}"];
          sourceDestCheck = false;

          modules = [
            inputs.bitte.profiles.common
            inputs.bitte.profiles.consul-common
            inputs.bitte.profiles.vault-cache
            openziti.nixosModules.ziti-controller
            openziti.nixosModules.ziti-router
            openziti.nixosModules.ziti-console
            openziti.nixosModules.ziti-edge-tunnel
            ./ziti.nix
            ./ziti-register.nix
            ({etcEncrypted, ...}: {
              # Substitute wg tunnel as temp drop in for zt
              # The AWS CIDR ranges could be source NATed here, but for debug purposes
              # they are currently being passed through the wg endpoint and are in the allowedIPs list
              # of the mac peers as they are unused ranges on the macs and make packet debugging easier.
              networking = {
                firewall.allowedUDPPorts = [51820];
                wireguard = {
                  enable = true;
                  interfaces.wg-zt = {
                    listenPort = 51820;
                    ips = ["10.10.0.254/32"];
                    privateKeyFile = "/etc/wireguard/private.key";
                    peers = [
                      # mm1
                      {
                        publicKey = "nvKCarVUXdO0WtoDsEjTzU+bX0bwWYHJAM2Y3XhO0Ao=";
                        allowedIPs = ["10.10.0.1/32" "10.10.0.101/32"];
                        persistentKeepalive = 30;
                      }
                      # mm2
                      {
                        publicKey = "VcOEVp/0EG4luwL2bMmvGvlDNDbCzk7Vkazd3RRl51w=";
                        allowedIPs = ["10.10.0.2/32" "10.10.0.102/32"];
                        persistentKeepalive = 30;
                      }
                    ];
                  };
                };
              };

              secrets.install.zt-wg-private = {
                source = "${etcEncrypted}/zt-wg-private";
                target = "/etc/wireguard/private.key";
                outputType = "binary";
                script = ''
                  chmod 0400 /etc/wireguard/private.key
                '';
              };

              secrets.install.zt-wg-public = {
                source = "${etcEncrypted}/zt-wg-public";
                target = "/etc/wireguard/public.key";
                outputType = "binary";
              };
            })
          ];

          securityGroupRules = {
            inherit
              (securityGroupRules)
              internal
              internet
              ssh
              ziti-controller-mgmt
              ziti-controller-rest
              ziti-router-edge
              ziti-router-fabric
              ;
            inherit
              (import ./sg.nix {inherit terralib lib;} config)
              wg
              ;
          };
        };
      };

      awsExtNodes = let
        # For each new machine provisioning to equinix:
        #   1) TF plan/apply in the `equinix` workspace to get the initial machine provisioning done after declaration
        #      `nix run .#clusters.ci-world.tf.equinix.[plan|apply]
        #   2) Record the privateIP attr that the machine is assigned in the nix metal code
        #   3) Add the provisioned machine to ssh config for deploy-rs to utilize
        #   4) Update the encrypted ssh config file with the new machine so others can easily pull the ssh config
        #   5) Deploy again with proper private ip, provisioning configuration and bitte stack modules applied
        #      `deploy -s .#$CLUSTER_NAME-$MACHINE_NAME --auto-rollback false --magic-rollback false
        deployType = "awsExt";
        node_class = "equinix";
        primaryInterface = "bond0";
        role = "client";

        # Equinix TF specific attrs
        project = config.cluster.name;
        plan = "m3.small.x86";

        baseEquinixMachineConfig = machineName:
          if builtins.pathExists ./equinix/${machineName}/configuration.nix != false
          then [./equinix/${machineName}/configuration.nix]
          else [];

        baseEquinixModuleConfig = [
          (bitte + /profiles/client.nix)
          (bitte + /profiles/multicloud/aws-extended.nix)
          (bitte + /profiles/multicloud/equinix.nix)
          openziti.nixosModules.ziti-edge-tunnel
          ({
            pkgs,
            lib,
            config,
            ...
          }: {
            services.ziti-edge-tunnel.enable = true;

            services.resolved = {
              # Vault agent does not seem to recognize successful lookups while resolved is in dnssec allow-downgrade mode
              dnssec = "false";

              # Ensure dnsmasq stays as the primary resolver while resolved is in use
              extraConfig = "Domains=~.";
            };

            # Extra prem diagnostic utils
            environment.systemPackages = with pkgs; [
              conntrack-tools
              ethtool
              icdiff
              iptstate
              tshark
            ];
          })
        ];

        buildkiteOnly = [
          ({lib, ...}: {
            # Temporarily disable nomad to avoid conflict with buildkite resource consumption
            services.nomad.enable = lib.mkForce false;
          })
        ];
      in {
        equinix-1 = {
          inherit deployType node_class primaryInterface role;
          equinix = {inherit plan project;};
          privateIP = "147.75.85.17";

          modules =
            baseEquinixModuleConfig
            ++ (baseEquinixMachineConfig "equinix-1")
            ++ buildkiteOnly
            ++ [
              ./buildkite/buildkite-agent-containers.nix
              (
                {
                  config,
                  lib,
                  ...
                }: let
                  cfg = config.services.buildkite-containers;
                in {
                  services.auto-gc = {
                    nixAutoMaxFreedGB = 150;
                    nixAutoMinFreeGB = 90;
                    nixHourlyMaxFreedGB = 600;
                    nixHourlyMinFreeGB = 150;
                    nixWeeklyGcFull = true;
                    nixWeeklyGcOnCalendar = "Sat *-*-* 20:00:00";
                  };

                  services.buildkite-containers.containerList = let
                    mkContainer = n: prio: {
                      containerName = "ci${cfg.hostIdSuffix}-${toString n}";
                      guestIp = "10.254.1.1${toString n}";
                      inherit prio;
                      tags = {
                        system = "x86_64-linux";
                        queue = "test";
                      };
                    };
                  in
                    map (n: mkContainer n (toString (10 - n))) (lib.range 1 5);
                }
              )
            ];
        };
      };
    };
  };
}
