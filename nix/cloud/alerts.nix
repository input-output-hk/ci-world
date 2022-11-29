{
  inputs,
  cell,
}: {
  ci-world-darwin = {
    datasource = "vm";
    rules = [
      {
        alert = "DarwinSshFailure";
        expr = ''probe_success{job="blackbox-ssh-darwin"} == 0'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = ''
            Cluster ssh connectivity to darwin builder {{ $labels.alias }} at {{ $labels.instance }}
             has been down for more than 5 minutes. Darwin CI capacity is degraded or down.'';
          summary = "Connectivity to Darwin builder {{ $labels.alias }} is down";
        };
      }
    ];
  };

  ci-world-spongix = {
    datasource = "vm";
    rules = [
      {
        alert = "SpongixRemoteCacheFailure";
        expr = ''rate(prometheus_spongix_remote_cache_fail)[1h] > 0'';
        for = "2m";
        labels.severity = "critical";
        annotations = {
          description = "Spongix service on {{ $labels.hostname }} has had {{ $value }} remote cache failure(s) in the past 1 hour.";
          summary = "Spongix service on {{ $labels.hostname }} had a remote cache failure";
        };
      }
    ];
  };

  ci-world-nomad-follower = {
    datasource = "loki";
    rules = [
      {
        alert = "NomadFollowerACLTokenNotFound";
        expr = ''sum(rate({syslog_identifier="nomad-follower"}[5m] |= `ACL token not found`)) by (host) > 0'';
        for = "1m";
        labels.severity = "critical";
        annotations = {
          description = ''
            Detected nomad-follower ACL issue on {{ $labels.host }}
            This may be due to a vault-agent issue and can usually be resolved
            by restarting both services.
            Without proper ACL, nomad-follower cannot send logs from Nomad jobs
            to Loki, and Cicero will not be able to display logs for actions.
          '';
          summary = "nomad-follower ACL issue on {{ $labels.host }}";
        };
      }
    ];
  };

  # inherit (inputs.bitte-cells.bitte.alerts)
  # ;
}
