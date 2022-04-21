{
  inputs,
  cell,
}: let
  namespaces = [
    "prod"
  ];
  components = [
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
    cluster = {
      name = "ci-prod";

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
        ci-prod = {description = "CI Prod";};
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
      locals.policies = {
        nomad.developer.namespace."*".policy = "deny";
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
