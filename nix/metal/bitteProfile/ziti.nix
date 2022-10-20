{lib, ...}: {
  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

  services = {
    ziti-router.enable = true;
    ziti-console.enable = true;
    ziti-edge-tunnel.enable = true;

    ziti-controller = {
      enable = true;
      extraBootstrapPost = ''
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
          --identity-roles '#gw-zet,#devOps' \
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
          --identity-roles '#gw-zet,#devOps' \
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
      '';
    };
  };
}
