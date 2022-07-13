{
  inputs,
  cell,
}:
{
  ci-world-alert-group-1 = {
    datasource = "vm";
    # concurrency = 1;         # Can override top level alert group details if needed, ex: concurrency default = 1
    # interval = "30s";        # Default = 1m
    rules = [
      {
        alert = "ci-world-custom-vm-alert-1";
        annotations = {
          description =
            "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 2 minutes.";
          summary =
            "Service {{ $labels.job }} is down on {{ $labels.instance }}";
        };
        expr = ''up{job=~"fakeJob|anotherFakeJob"} == 0'';
        for = "2m";
        labels = { severity = "critical"; };
      }
    ];
  };

  # inherit (inputs.bitte-cells.bitte.alerts)
  # ;
}

