{
  inputs,
  cell,
}: {
  # Postgrest
  workload-policies-postgrest = {
    tf.hydrate-cluster.configuration.locals.policies = {
      vault.postgrest = {
        path."kv/data/postgrest/*".capabilities = ["read" "list"];
        path."kv/metadata/postgrest/*".capabilities = ["read" "list"];
      };
    };

    # FIXME: consolidate policy reconciliation loop with TF
    # PROBLEM: requires bootstrapper reconciliation loop
    # clients need the capability to impersonate the `postgrest` role
    services.vault.policies.client = {
      path."auth/token/roles/postgrest".capabilities = ["read"];
    };
  };
}
