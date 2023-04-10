{lib, ...}: let
  awsExt-to-equinix-host-v1 = builtins.toJSON {
    allowedAddresses = ["10.12.10.0/24"];
    allowedPortRanges = [{low = 0; high = 65535;}];
    allowedProtocols = ["tcp" "udp"];
    forwardAddress = true;
    forwardPort = true;
    forwardProtocol = true;
    listenOptions = {identity = "$tunneler_id.name";};
  };

  awsExt-to-equinix-intercept-v1 = builtins.toJSON {
    addresses = ["10.12.10.0/24"];
    dialOptions = {
      connectTimeoutSeconds = 15;
      identity = "$dst_ip";
    };
    portRanges = [{low = 0; high = 65535;}];
    protocols = ["tcp" "udp"];
    sourceIp = "";
  };

  equinix-to-awsExt-host-v1 = builtins.toJSON {
    allowedAddresses = [
      "172.16.0.0/16"
      "10.24.0.0/16"
      "10.32.0.0/16"
      "10.52.0.0/16"
    ];
    allowedPortRanges = [{low = 0; high = 65535;}];
    allowedProtocols = ["tcp" "udp"];
    forwardAddress = true;
    forwardPort = true;
    forwardProtocol = true;
  };

  equinix-to-awsExt-intercept-v1 = builtins.toJSON {
    addresses = [
      "172.16.0.0/16"
      "10.24.0.0/16"
      "10.32.0.0/16"
      "10.52.0.0/16"
    ];
    dialOptions = {
      connectTimeoutSeconds = 15;
      identity = "";
    };
    portRanges = [{low = 0; high = 65535;}];
    protocols = ["tcp" "udp"];
    sourceIp = "";
  };

  darwin-ci-world-host-v1 = builtins.toJSON {
    address = "127.0.0.1";
    allowedPortRanges = [
      {low = 22; high = 22;}
      {low = 5900; high = 5900;}
      {low = 9100; high = 9100;}
    ];
    allowedProtocols = ["tcp"];
    forwardPort = true;
    forwardProtocol = true;
    listenOptions.identity = "$tunneler_id.name";
  };

  darwin-ci-world-intercept-v1 = builtins.toJSON {
    addresses = ["*.darwin.ci-world.ziti"];
    dialOptions.identity = "$dst_hostname";
    portRanges = [
      {low = 22; high = 22;}
      {low = 5900; high = 5900;}
      {low = 9100; high = 9100;}
    ];
    protocols = ["tcp"];
  };

in {
  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

  services = {
    ziti-router.enable = true;
    ziti-console.enable = true;
    ziti-edge-tunnel.enable = true;

    ziti-controller = {
      enable = true;
      extraBootstrapPost = ''
        # NOTE: Currently wg is preferred for darwin services until zet stabilizes for continous use, high bandwidth use case
        # Create mac-mini-1 builder service
        ziti edge create config mm1-builder-host.v1 \
          host.v1 \
          '{"address":"192.168.3.2","port":22,"protocol":"tcp"}'

        ziti edge create config mm1-builder-intercept.v1 \
          intercept.v1 \
          '{"addresses":["10.10.0.1/32"],"portRanges":[{"high":22,"low":22}],"protocols":["tcp"]}'

        ziti edge create service \
          mm1-builder \
          --configs mm1-builder-host.v1 \
          --configs mm1-builder-intercept.v1 \
          --encryption ON \
          --role-attributes mm1-builder

        ziti edge create service-policy \
          mm1-builder-dial \
          Dial \
          --identity-roles '#gw-zet,#devOps,#darwinDial' \
          --service-roles '@mm1-builder' \
          --semantic "AnyOf"

        ziti edge create service-policy \
          mm1-builder-bind \
          Bind \
          --identity-roles '#mac-mini-1.ziti' \
          --service-roles '@mm1-builder' \
          --semantic "AnyOf"

        # ----------------------------------------------

        # Create mac-mini-2 builder service
        ziti edge create config mm2-builder-host.v1 \
          host.v1 \
          '{"address":"192.168.3.2","port":22,"protocol":"tcp"}'

        ziti edge create config mm2-builder-intercept.v1 \
          intercept.v1 \
          '{"addresses":["10.10.0.2/32"],"portRanges":[{"high":22,"low":22}],"protocols":["tcp"]}'

        ziti edge create service \
          mm2-builder \
          --configs mm2-builder-host.v1 \
          --configs mm2-builder-intercept.v1 \
          --encryption ON \
          --role-attributes mm1-builder

        ziti edge create service-policy \
          mm2-builder-dial \
          Dial \
          --identity-roles '#gw-zet,#devOps,#darwinDial' \
          --service-roles '@mm2-builder' \
          --semantic "AnyOf"

        ziti edge create service-policy \
          mm2-builder-bind \
          Bind \
          --identity-roles '#mac-mini-2.ziti' \
          --service-roles '@mm2-builder' \
          --semantic "AnyOf"

        # ----------------------------------------------

        # Provision expected identities for enrollment to fulfill the service requirements
        # Note manual completion of enrollment on the target devices currently required

        mkdir -p enroll-jwts

        ziti edge create identity device zt-zet.ziti \
          --jwt-output-file enroll-jwts/ci-world-zt-zet.jwt \
          --role-attributes gw-zet

        ziti edge create identity device mac-mini-1.ziti \
          --jwt-output-file enroll-jwts/ci-world-mac-mini-1.jwt \
          --role-attributes mac-mini-1.ziti

        ziti edge create identity device mac-mini-2.ziti \
          --jwt-output-file enroll-jwts/ci-world-mac-mini-2.jwt \
          --role-attributes mac-mini-2.ziti

        # ----------------------------------------------

        # Create awsExt-to-equinix service
        # shellcheck disable=SC2016
        ziti edge create config awsExt-to-equinix-host-v1 host.v1 '${awsExt-to-equinix-host-v1}'

        # shellcheck disable=SC2016
        ziti edge create config awsExt-to-equinix-intercept-v1 intercept.v1 '${awsExt-to-equinix-intercept-v1}'

        ziti edge create service \
          awsExt-to-equinix \
          --configs awsExt-to-equinix-host-v1 \
          --configs awsExt-to-equinix-intercept-v1 \
          --encryption ON \
          --role-attributes awsExt-to-equinix

        ziti edge create service-policy \
          awsExt-to-equinix-dial \
          Dial \
          --identity-roles '#gw-zet' \
          --service-roles '@awsExt-to-equinix' \
          --semantic "AnyOf"

        ziti edge create service-policy \
          awsExt-to-equinix-bind \
          Bind \
          --identity-roles '#equinix' \
          --service-roles '@awsExt-to-equinix' \
          --semantic "AnyOf"

        # ----------------------------------------------

        # Create equinix-to-aws service
        ziti edge create config equinix-to-awsExt-host-v1 host.v1 '${equinix-to-awsExt-host-v1}'
        ziti edge create config equinix-to-awsExt-intercept-v1 intercept.v1 '${equinix-to-awsExt-intercept-v1}'

        ziti edge create service \
          equinix-to-awsExt \
          --configs equinix-to-awsExt-host-v1 \
          --configs equinix-to-awsExt-intercept-v1 \
          --encryption ON \
          --role-attributes equinix-to-awsExt

        ziti edge create service-policy \
          equinix-to-awsExt-dial \
          Dial \
          --identity-roles '#equinix' \
          --service-roles '@equinix-to-awsExt' \
          --semantic "AnyOf"

        ziti edge create service-policy \
          equinix-to-awsExt-bind \
          Bind \
          --identity-roles '#gw-zet' \
          --service-roles '@equinix-to-awsExt' \
          --semantic "AnyOf"

        # ----------------------------------------------

        # Create darwin access service
        # shellcheck disable=SC2016
        ziti edge create config "darwin.ci-world.host.v1" host.v1 '${darwin-ci-world-host-v1}'

        # shellcheck disable=SC2016
        ziti edge create config "darwin.ci-world.intercept.v1" intercept.v1 '${darwin-ci-world-intercept-v1}'

        ziti edge create service \
          darwin \
          --configs darwin.ci-world.host.v1 \
          --configs darwin.ci-world.intercept.v1 \
          --encryption ON \
          --role-attributes darwin

        ziti edge create service-policy \
          darwin-dial \
          Dial \
          --identity-roles '#devOps,#gw-zet,#darwinDial' \
          --service-roles '@darwin' \
          --semantic "AnyOf"

        ziti edge create service-policy \
          darwin-bind \
          Bind \
          --identity-roles '#darwin' \
          --service-roles '@darwin' \
          --semantic "AnyOf"
      '';
    };
  };
}
