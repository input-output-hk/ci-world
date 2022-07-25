{
  cell,
  inputs,
  domain,
  namespace,
  datacenters ? ["eu-central-1"],
}: let
  inherit (cell.library) ociNamer;
  inherit (cell) oci-images;
  inherit (inputs.nixpkgs) lib;
in {
  job.webhooks = {
    inherit datacenters namespace;

    group.webhooks = {
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

      network.port.http.to = "8080";

      service = [
        {
          name = "webhooks";
          address_mode = "auto";
          port = "http";
          tags = [
            "webhooks"
            "ingress"
            "traefik.enable=true"
            "traefik.http.routers.webhooks.rule=Host(`webhooks.${domain}`) && PathPrefix(`/`)"
            "traefik.http.routers.webhooks.entrypoints=https"
            "traefik.http.routers.webhooks.tls=true"
            "traefik.http.routers.webhooks.tls.certresolver=acme"
          ];
          check = [
            {
              type = "tcp";
              port = "http";
              interval = "10s";
              timeout = "2s";
            }
          ];
        }
      ];

      task.webhooks = {
        driver = "podman";

        config = {
          image = ociNamer oci-images.webhook-trigger;
          ports = ["http"];
          command = "${inputs.cicero.packages.webhook-trigger}/bin/trigger";
          args = lib.flatten [
            ["--port" "8080"]
            ["--secret-file" "/secrets/webhook"]
          ];
        };

        resources = {
          memory = 512;
          cpu = 300;
        };

        env = {
          NOMAD_ADDR = "https://nomad.${domain}";
          VAULT_ADDR = "https://vault.${domain}";
        };

        vault.policies = ["cicero"];

        template = [
          {
            destination = "secrets/webhook";
            data = ''
              {{with secret "kv/data/cicero/github"}}{{.Data.data.webhooks}}{{end}}
            '';
          }
        ];
      };
    };
  };
}
