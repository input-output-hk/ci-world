{
  pkgs,
  lib,
  ...
}: {
  # If this is needed, check there isn't a rogue logger first
  # services.loki.configuration.limits_config = {
  #   per_stream_rate_limit = "10MB";
  #   per_stream_rate_limit_burst = "30MB";
  # };

  # For API requests with huge responses, see:
  # - https://github.com/grafana/loki/issues/2271
  # - https://github.com/grafana/loki/issues/6568
  services.loki.configuration.server.grpc_server_max_recv_msg_size = 1024 * 1024 * 8; # 8 MiB

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
    mkTarget = ip: port: machine: {
      targets = ["${ip}:${toString port}"];
      labels.alias = machine;
    };
  in [
    {
      job_name = "blackbox-ssh-darwin";
      scrape_interval = "60s";
      metrics_path = "/probe";
      params.module = ["ssh_banner"];
      static_configs = [
        # Intel builders
        (mkTarget "10.10.0.1" 2201 "mm1-builder") # legacy
        (mkTarget "10.10.0.2" 2201 "mm2-builder") # legacy
        (mkTarget "10.10.0.3" 2201 "mm-intel3-builder")
        # (mkTarget "10.10.0.4" 2201 "mm-intel4-builder") -- currently allocated as signer only due to RAM constraint

        # Arm builders (x86_64 and aarch64)
        (mkTarget "10.10.0.51" 2201 "ms-arm1-builder")
        (mkTarget "10.10.0.52" 2201 "ms-arm2-builder")

        # Intel signers
        # (mkTarget "10.10.0.1" 2202 "mm1-signing") # legacy
        # (mkTarget "10.10.0.2" 2202 "mm2-signing") # legacy
        # (mkTarget "10.10.0.3" 2202 "mm-intel3-signing") -- currently allocated as builder only due to RAM constraint
        (mkTarget "10.10.0.4" 2202 "mm-intel4-signing")

        # Arm signers (x86_64 and aarch64)
        (mkTarget "10.10.0.51" 2202 "ms-arm1-signing")
        (mkTarget "10.10.0.52" 2202 "ms-arm2-signing")
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
    {
      job_name = "darwin-hosts-legacy";
      scrape_interval = "60s";
      metrics_path = "/monitorama/host";
      static_configs = [
        (mkTarget "10.10.0.1" 9111 "mm1-host")
        (mkTarget "10.10.0.2" 9111 "mm2-host")
      ];
    }
    {
      job_name = "darwin-hosts";
      scrape_interval = "60s";
      metrics_path = "/metrics";
      static_configs = [
        (mkTarget "10.10.0.3" 9100 "mm-intel3-host")
        (mkTarget "10.10.0.4" 9100 "mm-intel4-host")
        (mkTarget "10.10.0.51" 9100 "ms-arm1-host")
        (mkTarget "10.10.0.52" 9100 "ms-arm2-host")
      ];
    }
    {
      job_name = "darwin-ci-legacy";
      scrape_interval = "60s";
      metrics_path = "/monitorama/ci";
      static_configs = [
        (mkTarget "10.10.0.1" 9111 "mm1-builder")
        (mkTarget "10.10.0.2" 9111 "mm2-builder")
      ];
    }
    {
      job_name = "darwin-ci";
      scrape_interval = "60s";
      metrics_path = "/metrics";
      static_configs = [
        (mkTarget "10.10.0.3" 9101 "mm-intel3-builder")
        # (mkTarget "10.10.0.4" 9101 "mm-intel4-builder") -- currently allocated as signer only due to RAM constraint
        (mkTarget "10.10.0.51" 9101 "ms-arm1-builder")
        (mkTarget "10.10.0.52" 9101 "ms-arm2-builder")
      ];
    }
    # {
    #   job_name = "darwin-signing-legacy";
    #   scrape_interval = "60s";
    #   metrics_path = "/monitorama/signing";
    #   static_configs = [
    #     (mkTarget "10.10.0.1" 9111 "mm1-signing")
    #     (mkTarget "10.10.0.2" 9111 "mm2-signing")
    #   ];
    # }
    {
      job_name = "darwin-signing";
      scrape_interval = "60s";
      metrics_path = "/metrics";
      static_configs = [
        # (mkTarget "10.10.0.3" 9102 "mm-intel3-signing") -- currently allocated as builder only due to RAM constraint
        (mkTarget "10.10.0.4" 9102 "mm-intel4-signing")
        (mkTarget "10.10.0.51" 9102 "ms-arm1-signing")
        (mkTarget "10.10.0.52" 9102 "ms-arm2-signing")
      ];
    }

    {
      job_name = "devx-ci-linux";
      scrape_interval = "60s";
      metrics_path = "/metrics";
      static_configs = [
        (mkTarget "10.100.0.1" 9598 "ci1")
        (mkTarget "10.100.0.2" 9598 "ci2")
        (mkTarget "10.100.0.3" 9598 "ci3")
        (mkTarget "10.100.0.4" 9598 "ci4")
        (mkTarget "10.100.0.5" 9598 "ci5")
        (mkTarget "10.100.0.6" 9598 "ci6")
        (mkTarget "10.100.0.7" 9598 "ci7")
        (mkTarget "10.100.0.8" 9598 "ci8")
      ];
    }

    {
      job_name = "queue-runner";
      scrape_interval = "10s";
      metrics_path = "/hydra-stats";
      scheme = "https";
      tls_config.insecure_skip_verify = true;
      static_configs = [
        (mkTarget "10.100.0.1" 443 "ci1")
      ];
    }
  ];
}
