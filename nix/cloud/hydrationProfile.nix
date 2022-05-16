{
  inputs,
  cell,
}: let
  inherit (inputs.bitte-cells) patroni;
  namespaces = [
    "prod"
  ];
  components = [
    # Patroni bitte-cell
    "database"
  ];
in {
  default = {
    lib,
    config,
    terralib,
    ...
  }: let
    inherit (terralib) allowS3For;
    bucketArn = "arn:aws:s3:::${config.cluster.s3Bucket}";
    allowS3ForBucket = allowS3For bucketArn;

    inherit (terralib) var id;
    c = "create";
    r = "read";
    u = "update";
    d = "delete";
    l = "list";
    s = "sudo";

    secretsFolder = "encrypted";
    starttimeSecretsPath = "kv/nomad-cluster";
    runtimeSecretsPath = "runtime";
  in {
    imports = [
      (patroni.hydrationProfiles.hydrate-cluster namespaces)
    ];

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

      grafana.provision.dashboards = [
        {
          name = "provisioned-ci-world";
          options.path = ./dashboards;
        }
      ];
    };

    # cluster level
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

    # application secrets
    # --------------
    tf.hydrate-secrets.configuration = let
      _componentsXNamespaces = lib.cartesianProductOfSets {
        namespace = namespaces;
        component = components;
        stage = ["starttime"];
      };

      secretFile = g: ./. + "/${secretsFolder}/${g.namespace}/${g.component}-${g.namespace}-${g.stage}.enc.yaml";
      hasSecretFile = g: builtins.pathExists (secretFile g);

      secretsData.sops_file =
        builtins.foldl'
        (old: g:
          old
          // (lib.optionalAttrs (hasSecretFile g) {
            # Decrypting secrets from the files
            "${g.component}-secrets-${g.namespace}-${g.stage}".source_file = "${secretFile g}";
          }))
        {}
        _componentsXNamespaces;

      secretsResource.vault_generic_secret =
        builtins.foldl'
        (old: g:
          old
          // (
            lib.optionalAttrs (hasSecretFile g) (
              if g.stage == "starttime"
              then {
                # Loading secrets into the generic kv secrets resource
                "${g.component}-${g.namespace}-${g.stage}" = {
                  path = "${starttimeSecretsPath}/${g.namespace}/${g.component}";
                  data_json = var "jsonencode(yamldecode(data.sops_file.${g.component}-secrets-${g.namespace}-${g.stage}.raw))";
                };
              }
              else {
                # Loading secrets into the generic kv secrets resource
                "${g.component}-${g.namespace}-${g.stage}" = {
                  path = "${runtimeSecretsPath}/${g.namespace}/${g.component}";
                  data_json = var "jsonencode(yamldecode(data.sops_file.${g.component}-secrets-${g.namespace}-${g.stage}.raw))";
                };
              }
            )
          ))
        {}
        _componentsXNamespaces;
    in {
      data = secretsData;
      resource = secretsResource;
    };

    # application state
    # --------------
    tf.hydrate-app.configuration = let
    in {};
  };
}
