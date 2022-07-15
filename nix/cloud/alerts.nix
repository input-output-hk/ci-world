{
  inputs,
  cell,
}: {
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

  # inherit (inputs.bitte-cells.bitte.alerts)
  # ;
}
