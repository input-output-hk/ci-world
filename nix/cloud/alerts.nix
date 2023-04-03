{
  inputs,
  cell,
}: {
  ci-world-loki = {
    datasource = "loki";
    rules = [
      {
        alert = "CoredumpDetected";
        expr = ''sum(rate({syslog_identifier="systemd-coredump", host=~"core.*"}[1h] != "sshd" |= "dumped core")) by (host) > 0'';
        for = "1m";
        labels.severity = "critical";
        annotations = {
          description = ''
            Detected a coredump on {{ $labels.host }}.
             This usually requires attention and most likely manual intervention.
             To analyze a coredump, run `coredumpctl list` on the affected machine, and run `coredump debug $id` in a nix shell with gdb.'';
          summary = "Detected a coredump on {{ $labels.host }}";
        };
      }
    ];
  };

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

  ci-world-node-exporter = {
    datasource = "vm";
    rules = [
      {
        alert = "node_down";
        expr = ''up  == 0'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "{{$labels.alias}} of instance {{$labels.instance}} in job {{$labels.job}} has been down for more than 5 minutes.";
          summary = "{{$labels.alias}}: Node is down.";
        };
      }
      {
        alert = "node_filesystem_full_90percent";
        expr = ''sort(node_filesystem_free_bytes{device!~"ramfs|9pfs",fstype!="apfs"} < node_filesystem_size_bytes{device!="ramfs",fstype!="apfs"} * 0.1) / 1024^3'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "{{$labels.alias}} of instance {{$labels.instance}} and device {{$labels.device}} on {{$labels.mountpoint}} has less than 10% space left on its filesystem.";
          summary = "{{$labels.alias}}: Filesystem is running out of space soon.";
        };
      }
      {
        alert = "node_filesystem_full_in_4h";
        expr = ''predict_linear(node_filesystem_free_bytes{device!~"ramfs|tmpfs|9pfs|none",fstype!~"apfs|autofs|ramfs|cd9660"}[4h], 4*3600) <= 0'';
        for = "5m";
        labels.severity = "warning";
        annotations = {
          description = "{{$labels.alias}} of instance {{$labels.instance}} and  device {{$labels.device}} on {{$labels.mountpoint}} is running out of space of in approx. 4 hours";
          summary = "{{$labels.alias}}: Filesystem is running out of space in 4 hours.";
        };
      }
      {
        alert = "node_ram_using_90percent";
        expr = ''node_memory_MemFree_bytes + node_memory_Buffers_bytes + node_memory_Cached_bytes < node_memory_MemTotal_bytes * 0.10'';
        for = "30m";
        labels.severity = "critical";
        annotations = {
          description = "{{$labels.alias}} of instance {{$labels.instance}} in job {{$labels.job}} is using at least 90% of its RAM for at least 30 minutes now.";
          summary = "{{$labels.alias}}: High RAM utilization.";
        };
      }
      {
        alert = "node_swap_using_80percent";
        expr = ''node_memory_SwapTotal_bytes - (node_memory_SwapFree_bytes + node_memory_SwapCached_bytes) > node_memory_SwapTotal_bytes * 0.8'';
        for = "10m";
        labels.severity = "warning";
        annotations = {
          description = "{{$labels.alias}} of instance {{$labels.instance}} in job {{$labels.job}} is using 80% of its swap space for at least 10 minutes now.";
          summary = "{{$labels.alias}}: Running out of swap soon.";
        };
      }
      {
        alert = "node_time_unsync";
        expr = ''abs(node_timex_offset_seconds) > 0.500 or node_timex_sync_status != 1'';
        for = "10m";
        labels.severity = "warning";
        annotations = {
          description = "{{$labels.alias}} of instance {{$labels.instance}} in job {{$labels.job}} has local clock offset too large or out of sync with NTP";
          summary = "{{$labels.alias}}: Clock out of sync with NTP";
        };
      }
    ];
  };

  # We are customizing just about every bitte-cells bitte-system alert rule now, so no point filtering from upstream.
  # We'll define our own full set here instead.
  bitte-system-modified = {
    datasource = "vm";
    rules = [
      {
        alert = "SystemCpuUsedAlert";
        expr = ''100 - cpu_usage_idle{cpu="cpu-total",host!~"ip-.*|equinix.*"} > 90'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "CPU has been above 90% on {{ $labels.host }} for more than 5 minutes.";
          summary = "[System] CPU Used alert on {{ $labels.host }}";
        };
      }
      {
        alert = "SystemCpuUsedAlertEquinix";
        expr = ''100 - cpu_usage_idle{cpu="cpu-total",host=~"equinix.*"} > 90'';
        for = "4h";
        labels.severity = "critical";
        annotations = {
          description = "CPU has been above 90% on {{ $labels.host }} for more than 4 hours.";
          summary = "[System] CPU Used alert on {{ $labels.host }}";
        };
      }
      {
        alert = "SystemMemoryUsedAlert";
        expr = ''mem_used_percent{host!~"equinix.*"} > 90'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "Memory used has been above 90% for more than 5 minutes.";
          summary = "[System] Memory Used alert on {{ $labels.host }}";
        };
      }
      {
        alert = "SystemMemoryUsedAlertEquinix";
        expr = ''mem_used_percent{host=~"equinix.*"} > 90'';
        for = "4h";
        labels.severity = "critical";
        annotations = {
          description = "Memory used has been above 90% for more than 4 hours.";
          summary = "[System] Memory Used alert on {{ $labels.host }}";
        };
      }
      {
        alert = "SystemDiskUsedSlashAlert";
        expr = ''disk_used_percent{path="/"} > 80'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "Disk used on {{ $labels.host }} on mount / has been above 80% for more than 5 minutes.";
          summary = "[System] Disk used / alert on {{ $labels.host }}";
        };
      }

      {
        alert = "SystemDiskUsedSlashPredictedAlert";
        expr = ''predict_linear(disk_used_percent{path="/"}[1h], 12 * 3600) > 90 and on(host) disk_used_percent{path="/"} > 20'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "Linear extrapolation predicts disk usage on {{ $labels.host }} will be above 90% within 12 hours and is greater than 20% capacity utilized now.";
          summary = "[System] Predicted Disk used / alert on {{ $labels.host }}";
        };
      }
      {
        alert = "SystemDiskUsedVarClientAlert";
        expr = ''disk_used_percent{path="/var"} > 80'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "Disk used on client {{ $labels.host }} /var has been above 80% for more than 5 minutes.";
          summary = "[System] Disk used Clients /var alert on {{ $labels.host }}";
        };
      }
      {
        alert = "SystemDiskUsedVarClientPredictedAlert";
        expr = ''predict_linear(disk_used_percent{path="/var"}[1h], 12 * 3600) > 90 and on(host) disk_used_percent{path="/var"} > 20'';
        for = "5m";
        labels.severity = "critical";
        annotations = {
          description = "Linear extrapolation predicts client disk usage on /var on {{ $labels.host }} will be above 90% within 12 hours and is greater than 20% capacity utilized now.";
          summary = "[System] Predicted Disk used clients /var alert on {{ $labels.host }}";
        };
      }
    ];
  };

  # inherit (inputs.bitte-cells.bitte.alerts)
  # ;
}
