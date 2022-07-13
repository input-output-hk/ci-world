{
  inputs,
  cell,
}: let
  inherit (inputs) bitte-cells;
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
    };

    services = {
      nomad.namespaces = {
        prod = {description = "CI Prod";};
      };
    };

    # cluster level (terraform)
    # --------------
    tf.hydrate-cluster.configuration = {
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
        };
      };
    };

    # Observability State
    # --------------
    tf.hydrate-monitoring.configuration = {
      resource = inputs.bitte-cells._utils.library.mkMonitoring
      # Alert attrset
      {
        inherit (cell.alerts)
          # moe-world-alert-group-1
          # Upstream alerts which may have downstream deps can be imported here
          ;
        # Upstream alerts not having downstream deps can be directly imported here
        inherit (inputs.bitte-cells.bitte.alerts)
          bitte-deadmanssnitch
          bitte-loki
          bitte-vm-health
          bitte-vm-standalone
          bitte-vmagent
          ;
      }
      # Dashboard attrset
      {
        # Organelle local declared dashboards
        inherit (cell.dashboards)
          ci-world-spongix
          ;

        # Upstream dashboards not having downstream deps can be directly imported here
        inherit (inputs.bitte-cells.bitte.dashboards)
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
