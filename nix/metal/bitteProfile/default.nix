{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs;
  inherit (inputs.bitte-cells) patroni;
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
      s3CachePubKey = lib.fileContents ./encrypted/nix-public-key-file;
      flakePath = "${inputs.self}";

      builder = "cache";

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

            systemd.services.nomad.serviceConfig = {
              JobTimeoutSec = "600s";
              JobRunningTimeoutSec = "600s";
            };
          })
        ];

        mkAsgs = region: desiredCapacity: instanceType: volumeSize: node_class: asgSuffix: opts: extraConfig:
          {
            inherit region desiredCapacity instanceType volumeSize node_class asgSuffix;
            modules =
              defaultModules
              ++ lib.optional (opts ? withPatroni && opts.withPatroni == true) (patroni.nixosProfiles.client node_class);
          }
          // extraConfig;
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
            (mkAsgs "eu-central-1" 1 "m5.8xlarge" 500 "prod" "prod1a" {withPatroni = true;} {vpcZoneIdentifierSuffix = ["a"];})
            (mkAsgs "eu-central-1" 1 "m5.8xlarge" 500 "prod" "prod1b" {withPatroni = true;} {vpcZoneIdentifierSuffix = ["b"];})
            (mkAsgs "eu-central-1" 1 "m5.8xlarge" 500 "prod" "prod1c" {withPatroni = true;} {vpcZoneIdentifierSuffix = ["c"];})
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

          modules = [bitte.profiles.monitoring];

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
            ({etcEncrypted, ...}: {
              services.traefik = {
                # Enables cert management via job tabs vs extraSANs
                acmeDnsCertMgr = false;

                # Changing to default of false soon
                useDockerRegistry = false;

                # Changing to a default of true soon
                useVaultBackend = true;
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
          volumeSize = 600;

          modules = [
            (bitte + /profiles/auxiliaries/telegraf.nix)
            (bitte + /profiles/auxiliaries/docker-registry.nix)
            ./builder.nix
            ./spongix-user.nix
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };
      };
    };
  };
}
