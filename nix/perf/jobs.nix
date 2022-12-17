{
  cell,
  inputs,
}: let
  inherit (cell) oci-images;
  ociNamer = oci: builtins.unsafeDiscardStringContext "${oci.imageName}:${oci.imageTag}";
in {
  default = {
    namespace,
    datacenters,
    nodeClass,
    domain,
    ...
  }: let
    url = "perf.ci.iog.io";
    secrets = {
      __toString = _: "kv/postgrest/${namespace}";
      postgrestDbUser = ".Data.data.postgrestDbUser";
      postgrestDbPass = ".Data.data.postgrestDbPass";
      jwtSecret = ".Data.data.jwtSecret";
    };
  in {
    job.postgrest = {
      inherit datacenters namespace;
      constraint = [
        {
          attribute = "\${node.class}";
          operator = "=";
          value = "${nodeClass}";
        }
        {
          operator = "distinct_property";
          attribute = "\${attr.unique.hostname}";
          value = 1;
        }
      ];

      vault.policies = ["postgrest"];

      group.postgrest = {
        network = {
          mode = "bridge";
          dns = {servers = ["172.17.0.1"];};
          port.postgrest = {};
          port.adminserver = {};
        };

        restart = {
          attempts = 5;
          delay = "10s";
          interval = "1m";
          mode = "delay";
        };

        reschedule = {
          delay = "10s";
          delay_function = "exponential";
          max_delay = "1m";
          unlimited = true;
        };

        task.postgrest = {
          driver = "docker";

          config.image = ociNamer oci-images.postgrest;

          resources = {
            # Start with optimization for t3a.medium AWS class;
            memory = 3 * 1024;
            cpu = 3500;
          };

          env = {
            # DEBUG_SLEEP = "600";
          };

          template = [
            {
              change_mode = "restart";
              data = let
                getSecret = secret: ''{{ with secret "${secrets}" }}{{${secret}}}{{end}}'';
                address = "_prod-database._master.service.eu-central-1.consul";
                db = "perf";
                user = getSecret secrets.postgrestDbUser;
                pass = getSecret secrets.postgrestDbPass;
                jwtSecret = getSecret secrets.jwtSecret;
              in ''
                # postgrest.conf

                # The standard connection URI format, documented at
                # https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING
                db-uri = "postgres://${user}:${pass}@${address}:5432/${db}?sslmode=require"

                # The database role to use when no client authentication is provided.
                # Should differ from authenticator
                db-anon-role = "anon"

                # The secret to verify the JWT for authenticated requests with.
                # Needs to be 32 characters minimum.
                jwt-secret           = "${jwtSecret}"
                jwt-secret-is-base64 = false

                # Port the postgrest process is listening on for http requests
                server-port = {{ env "NOMAD_PORT_postgrest" }}

                # Admin server used for checks.
                admin-server-port = {{ env "NOMAD_PORT_adminserver" }}
              '';
              destination = "secrets/postgrest.conf";
              env = false;
            }
          ];

          service = [
            {
              address_mode = "auto";
              check = [
                {
                  name = "live";
                  address_mode = "host";
                  type = "http";
                  port = "adminserver";
                  path = "/live";
                  interval = "30s";
                  timeout = "5s";
                }
                {
                  name = "ready";
                  address_mode = "host";
                  type = "http";
                  port = "adminserver";
                  path = "/ready";
                  interval = "30s";
                  timeout = "5s";
                }
              ];
              name = "${namespace}-postgrest";
              port = "postgrest";
              tags = [
                "${namespace}"
                "\${NOMAD_ALLOC_ID}"
                "ingress"
                "traefik.enable=true"
                "traefik.http.routers.postgrest.rule=Host(`${url}`)"
                "traefik.http.routers.postgrest.entrypoints=https"
                "traefik.http.routers.postgrest.tls.certresolver=acme"
              ];
            }
          ];
        };
      };
    };
  };
}
