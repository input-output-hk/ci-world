{
  inputs,
  cell,
}: {
  ociNamer = oci: builtins.unsafeDiscardStringContext "${oci.imageName}:${oci.imageTag}";
  pp = v: builtins.trace (builtins.toJSON v) v;

  # Adds arguments that enable nix support inside the container.
  addN2cNixArgs =
    # This must include all dependencies used in the image to allow nix builds
    # in the container (Nix won't know about paths otherwise and fail on trying
    # to write read-only data).
    closureRootPaths:
    # The arguments to nix2container's buildImage or buildLayer function to enrich.
    args: let
      inherit (inputs.nixpkgs) lib cacert symlinkJoin closureInfo runCommand;

      closure = closureInfo {
        rootPaths = {inherit cacert;} // closureRootPaths;
      };

      global = runCommand "global" {} ''
        mkdir -p $out $out/etc
        cp ${closure}/registration $out

        echo 'root:x:0:' > $out/etc/group
        echo 'nixbld:x:30000:nixbld1' > $out/etc/group

        echo 'root:!:0:0::/local:/bin/bash' > $out/etc/passwd
        echo 'nixbld1:!:30001:30000:Nix build user 1:/var/empty:/bin/nologin' >> $out/etc/passwd
      '';

      nixConf = runCommand "nix.conf" {} ''
        mkdir -p $out/etc/nix
        cat > $out/etc/nix/nix.conf <<'EOF'
        # If /dev/kvm does not actually exist in the container
        # we would rather build without KVM than fail.
        extra-system-features = kvm

        experimental-features = nix-command flakes

        show-trace = true
        EOF
      '';

      tmp = runCommand "tmp" {} ''
        mkdir -p $out/tmp
      '';
    in
      args
      // {
        config =
          args.config
          or {}
          // {
            Env = lib.mapAttrsToList (n: v: "${n}=${v}") {
              SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
            };
          };
        contents =
          args.contents
          or []
          ++ [
            (symlinkJoin {
              name = "deps";
              paths = with inputs.nixpkgs; [
                cacert
                gitMinimal
              ];
            })
            global
            nixConf
            tmp
          ];
        perms =
          args.perms
          or []
          ++ [
            {
              path = tmp;
              regex = ".*";
              mode = "1777";
            }
          ];
      };
}
