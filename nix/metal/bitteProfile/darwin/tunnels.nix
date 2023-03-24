wgAddresses: {
  inputs,
  system,
  pkgs,
  lib,
  ...
}: let
  zet = inputs.openziti.packages.${system}.ziti-edge-tunnel_latest;
in {
  environment.systemPackages = [zet];

  networking.wg-quick.interfaces.wg = {
    preUp = [''echo "Starting wireguard wg interface at $(date)"''];
    autostart = true;
    address = [wgAddresses.ci wgAddresses.signing];
    listenPort = 51820;
    privateKeyFile = "/var/root/.keys/wireguard-private.key";
    peers = [
      {
        endpoint = "zt.bitte.aws.iohkdev.io:51820";
        allowedIPs = ["10.10.0.254/32"];
        publicKey = "WDbI9dSxkddMlqUDpm4teKwdtTCzLQWQsi1ecUqlgks=";
        persistentKeepalive = 30;
      }
    ];
  };

  launchd.daemons.wg-quick-wg.serviceConfig = {
    # The default wg-quick module no longer works properly on Ventura with the default keepalive options.
    KeepAlive = lib.mkForce true;

    # The default program args with a direct path to the script in the nix store fails to
    # run in launchctl with an err code of '78'.
    ProgramArguments = lib.mkForce ["/run/current-system/sw/bin/wg-quick" "up" "wg"];
  };

  launchd.daemons.ziti-edge-tunnel = {
    # Without providing a route package a route cmd not found error is thrown on some startups.
    # However, nettools is deprecated and insecure, so add the path to the macOS system native route cmd.
    path = with pkgs; [coreutils gawk gnugrep gnused zet "/sbin"];
    serviceConfig = {
      KeepAlive = true;
      StandardOutPath = "/var/log/ziti-edge-tunnel.log";
      StandardErrorPath = "/var/log/ziti-edge-tunnel.log";
    };
    script = ''
      echo "Starting ZET at $(date)"
      mkdir -p /var/root/ziti/identity
      chown -R root:root /var/root/ziti
      chmod 0700 /var/root/ziti/identity
      chmod 0600 /var/root/ziti/identity/*

      # On darwin, ZET throws an abort signal if these json file aren't cleared between runs
      rm /tmp/config.json*

      ziti-edge-tunnel run -I /var/root/ziti/identity/
    '';
  };

  # Required rules for wireguard and ziti ip redirection from host to guest
  system.activationScripts.postActivation.text = let
    appendLines = "$'\\n''rdr-anchor \"org.nixos.vm-rdr\"'$'\\\n''load anchor \"org.nixos.vm-rdr\" from \"/etc/pf.anchors/org.nixos.vm-rdr\"'";
    anchorText = ''
      rdr pass on { utun1, utun2 } inet proto tcp to ${wgAddresses.ci} port ssh -> 192.168.64.2/32 port ssh
      rdr pass on { utun1, utun2 } inet proto tcp to ${wgAddresses.signing} port ssh -> 192.168.64.3/32 port ssh'';
  in ''
    # Ensure packet forwarding to vm guests is enabled
    printf "applying darwin guest packet redirection... "
    mkdir -p /etc/pf.anchors
    echo '${anchorText}' > /etc/pf.anchors/org.nixos.vm-rdr

    if ! grep --quiet --no-messages 'org.nixos.vm-rdr' /etc/pf.conf; then
      cp /etc/pf.conf /etc/pf.conf-orig

      APPEND_LINES=${appendLines}

      # Requires gnused for proper pattern interpretation; bsd sed fails
      ${pkgs.gnused}/bin/sed -i -e '\|rdr-anchor "com.apple/\*"|a\'"$APPEND_LINES" /etc/pf.conf

      echo "done, a reboot may be required"
    else
      echo "ok"
    fi
  '';

  # Create a pfctl packet routing enablement reference service
  launchd.daemons.pfctl-vm-rdr = {
    serviceConfig = {
      Disabled = false;
      WorkingDirectory = "/var/run";
      Program = "/sbin/pfctl";
      ProgramArguments = [
        "pfctl"
        "-E"
        "-f"
        "/etc/pf.conf"
      ];
      RunAtLoad = true;
      StandardOutPath = "/var/log/pfctl-vm-rdr.log";
      StandardErrorPath = "/var/log/pfctl-vm-rdr.log";
    };
  };
}
