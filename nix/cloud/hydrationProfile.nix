{
  inputs,
  cell,
}: let
  inherit (inputs) bitte-cells cells;
in {
  # Bitte Hydrate Module
  # -----------------------------------------------------------------------

  default = {
    lib,
    bittelib,
    ...
  }: {
    imports = [
      (bitte-cells.patroni.hydrationProfiles.hydrate-cluster ["prod"])
      (bitte-cells.tempo.hydrationProfiles.hydrate-cluster ["prod"])
      (cells.perf.hydrationProfile.workload-policies-postgrest)
    ];

    # NixOS-level hydration
    # --------------

    cluster = {
      name = "ci-world";

      adminNames = ["john.lotoski"];
      developerGithubNames = [];
      developerGithubTeamNames = [];
      domain = "ci.iog.io";
      extraAcmeSANs = [];
      kms = "arn:aws:kms:eu-central-1:074718059002:key/5bb7cc1b-151c-4841-bcb3-622bc8df4b5a";
      s3Bucket = "iohk-ci-bitte";
      s3Tempo = "iohk-ci-tempo";
    };

    services = {
      nomad.namespaces = {
        prod = {description = "CI Prod";};
        baremetal = {description = "CI Baremetal Builders";};
        perf = {description = "CI Performance Benchmarking";};
      };
    };

    # cluster level (terraform)
    # --------------
    tf.hydrate-cluster.configuration = tfHydrateCluster: {
      resource.vault_github_team.marlowe-devops = {
        backend = "\${vault_github_auth_backend.employee.path}";
        team = "plutus-devops";
        policies = ["developer" "default"];
      };

      resource.vault_github_user.cicero-rschardt = {
        backend = "\${vault_github_auth_backend.employee.path}";
        user = "rschardt";
        policies = ["cicero"];
      };

      resource.vault_github_team.performance-tracing = {
        backend = "\${vault_github_auth_backend.employee.path}";
        team = "performance-tracing";
        policies = ["perf"];
      };

      resource = {
        aws_s3_bucket.cicero-public.bucket = "cicero-public";

        aws_s3_bucket_ownership_controls =
          lib.mkIf
          (
            lib.versionAtLeast
            tfHydrateCluster.config.terraform.required_providers.aws.version
            "3.68.0" # https://github.com/hashicorp/terraform-provider-aws/issues/21980#issuecomment-984631427
          )
          (
            __trace ''
              The Terraform AWS provider is recent enough to support S3 object ownership "BucketOwnerEnforced".
              You can remove the version check for aws_s3_bucket_ownership_controls.cicero-public in nix/cloud/hydrationProfile.nix.
            '' {
              cicero-public = {
                bucket = "\${aws_s3_bucket.cicero-public.bucket}";
                rule.object_ownership = "BucketOwnerEnforced";
              };
            }
          );

        aws_s3_bucket_public_access_block.cicero-public = {
          bucket = "\${aws_s3_bucket.cicero-public.bucket}";
          block_public_acls = false;
          block_public_policy = false;
          ignore_public_acls = false;
          restrict_public_buckets = false;

          depends_on = [
            # https://github.com/hashicorp/terraform-provider-aws/issues/7628#issuecomment-469825984
            "aws_s3_bucket_policy.cicero-public"
          ];
        };

        aws_s3_bucket_policy.cicero-public = {
          bucket = "\${aws_s3_bucket.cicero-public.bucket}";
          policy = "\${data.aws_iam_policy_document.cicero-public.json}";
        };

        vault_aws_secret_backend_role.cicero = {
          backend = "aws";
          name = "cicero";
          credential_type = "iam_user";
          policy_document = "\${data.aws_iam_policy_document.cicero.json}";
        };
      };

      data.aws_iam_policy_document = {
        cicero-public.statement = [
          {
            principals = [
              {
                type = "*";
                identifiers = ["*"];
              }
            ];
            actions = ["s3:GetObject"];
            resources = ["arn:aws:s3:::cicero-public/*"];
          }
        ];

        cicero.statement = [
          {
            actions = ["s3:PutObject"];
            resources = ["arn:aws:s3:::cicero-public/*"];
          }
        ];
      };

      locals.policies = {
        consul.developer.servicePrefix."marlowe-" = {
          policy = "write";
          intentions = "write";
        };

        vault = let
          c = "create";
          r = "read";
          u = "update";
          d = "delete";
          l = "list";
          s = "sudo";
          caps = lib.mapAttrs (n: v: {capabilities = v;});
        in {
          admin.path = caps {
            "secret/*" = [c r u d l];
            "auth/github-terraform/map/users/*" = [c r u d l s];
            "auth/github-employees/map/users/*" = [c r u d l s];
          };

          terraform.path = caps {
            "secret/data/vbk/*" = [c r u d l];
            "secret/metadata/vbk/*" = [d];
          };

          vit-terraform.path = caps {
            "secret/data/vbk/vit-testnet/*" = [c r u d l];
            "secret/metadata/vbk/vit-testnet/*" = [c r u d l];
          };

          cicero.path = caps {
            "auth/token/lookup" = [u];
            "auth/token/lookup-self" = [r];
            "auth/token/renew-self" = [u];
            "kv/data/cicero/*" = [r l];
            "kv/metadata/cicero/*" = [r l];
            "nomad/creds/cicero" = [r u];
            "aws/creds/cicero" = [r u];
          };

          client.path = caps {
            "auth/token/create" = [u s];
            "auth/token/create/nomad-cluster" = [u];
            "auth/token/create/nomad-server" = [u];
            "auth/token/lookup" = [u];
            "auth/token/lookup-self" = [r];
            "auth/token/renew-self" = [u];
            "auth/token/revoke-accessor" = [u];
            "auth/token/roles/nomad-cluster" = [r];
            "auth/token/roles/nomad-server" = [r];
            "consul/creds/consul-agent" = [r];
            "consul/creds/consul-default" = [r];
            "consul/creds/consul-register" = [r];
            "consul/creds/nomad-client" = [r];
            "consul/creds/vault-client" = [r];
            "kv/data/bootstrap/clients/*" = [r];
            "kv/data/bootstrap/static-tokens/clients/*" = [r];
            "kv/data/nomad-cluster/*" = [r l];
            "kv/metadata/nomad-cluster/*" = [r l];
            "nomad/creds/nomad-follower" = [r u];
            "pki/issue/client" = [c u];
            "pki/roles/client" = [r];
            "sys/capabilities-self" = [u];
          };

          perf.path = caps {
            "auth/token/lookup" = [u];
            "auth/token/lookup-self" = [r];
            "auth/token/renew-self" = [u];
            "sys/capabilities-self" = [u];
            "kv/data/postgrest/*" = [r l];
            "kv/metadata/postgrest/*" = [r l];
            "nomad/creds/perf" = [r u];
            "consul/creds/developer" = [r u];
            "sops/keys/dev" = [r l];
            "sops/decrypt/dev" = [r u l];
            "sops/encrypt/dev" = [r u l];
          };
        };

        nomad = {
          admin = {
            description = "Admin policies";
            namespace."*" = {
              policy = "write";
              capabilities = [
                "alloc-exec"
                "alloc-lifecycle"
                "alloc-node-exec"
                "csi-list-volume"
                "csi-mount-volume"
                "csi-read-volume"
                "csi-register-plugin"
                "csi-write-volume"
                "dispatch-job"
                "list-jobs"
                "list-scaling-policies"
                "read-fs"
                "read-job"
                "read-job-scaling"
                "read-logs"
                "read-scaling-policy"
                "scale-job"
                "submit-job"
              ];
            };
          };

          developer = {
            description = "Dev policies";

            namespace."*".policy = "deny";

            namespace."prod" = {
              policy = "read";
              capabilities = [
                "list-jobs"
                "list-scaling-policies"
                "read-fs"
                "read-job"
                "read-job-scaling"
                "read-logs"
                "read-scaling-policy"
              ];
            };

            namespace."marlowe" = {
              policy = "write";
              capabilities = [
                "alloc-exec"
                "alloc-lifecycle"
                "dispatch-job"
                "list-jobs"
                "list-scaling-policies"
                "read-fs"
                "read-job"
                "read-job-scaling"
                "read-logs"
                "read-scaling-policy"
                "scale-job"
                "submit-job"
              ];
            };
            node.policy = "read";
            host_volume."marlowe".policy = "write";
          };

          cicero = {
            description = "Cicero (Run Jobs and monitor them)";
            agent.policy = "read";
            node.policy = "read";
            namespace."*" = {
              policy = "read";
              capabilities = [
                "alloc-lifecycle"
                "submit-job"
                "dispatch-job"
                "read-logs"
                "read-job"
              ];
            };
            host_volume."marlowe".policy = "write";
          };

          perf = {
            description = "Performance tracing and benchmarking policies";

            namespace."*".policy = "deny";

            namespace."perf" = {
              policy = "write";
              capabilities = [
                "alloc-exec"
                "alloc-lifecycle"
                "dispatch-job"
                "list-jobs"
                "list-scaling-policies"
                "read-fs"
                "read-job"
                "read-job-scaling"
                "read-logs"
                "read-scaling-policy"
                "scale-job"
                "submit-job"
              ];
            };
            node.policy = "read";
          };
        };
      };
    };

    # Observability State
    # --------------
    tf.hydrate-monitoring.configuration = {
      resource =
        inputs.bitte-cells._utils.library.mkMonitoring
        # Alert attrset
        {
          # Cell block local declared alerts
          inherit
            (cell.alerts)
            ci-world-darwin
            ci-world-loki
            ci-world-node-exporter
            ci-world-nomad-follower
            ci-world-spongix
            bitte-system-modified
            ;

          inherit
            (inputs.bitte-cells.bitte.alerts)
            bitte-consul
            bitte-deadmanssnitch
            bitte-vault
            bitte-vm-health
            bitte-vm-standalone
            bitte-vmagent
            ;

          inherit
            (inputs.bitte-cells.patroni.alerts)
            bitte-cells-patroni
            ;

          inherit
            (inputs.bitte-cells.tempo.alerts)
            bitte-cells-tempo
            ;
        }
        # Dashboard attrset
        {
          # Cell block local declared dashboards
          inherit
            (cell.dashboards)
            ci-world-mac-mini-zfs
            ci-world-node-exporter
            ci-world-spongix
            ;

          # Upstream dashboards not having downstream deps can be directly imported here
          inherit
            (inputs.bitte-cells.bitte.dashboards)
            bitte-consul
            bitte-log
            bitte-loki
            bitte-nomad
            bitte-system
            bitte-traefik
            bitte-vault
            bitte-vmagent
            bitte-vmalert
            bitte-vm
            bitte-vulnix
            ;

          inherit
            (inputs.bitte-cells.patroni.dashboards)
            bitte-cells-patroni
            ;

          inherit
            (inputs.bitte-cells.tempo.dashboards)
            bitte-cells-tempo-operational
            bitte-cells-tempo-reads
            bitte-cells-tempo-writes
            ;
        };
    };

    # application state (terraform)
    # --------------
    tf.hydrate-app.configuration = let
      vault' = {
        dir = ./. + "/kv/vault";
        prefix = "kv";
      };
      # consul' = {
      #   dir = ./. + "/kv/consul";
      #   prefix = "config";
      # };
      vault = bittelib.mkVaultResources {inherit (vault') dir prefix;};
      # consul = bittelib.mkConsulResources {inherit (consul') dir prefix;};
    in {
      data = {inherit (vault) sops_file;};
      resource = {
        inherit (vault) vault_generic_secret;
        # inherit (consul) consul_keys;
      };
    };
  };
}
