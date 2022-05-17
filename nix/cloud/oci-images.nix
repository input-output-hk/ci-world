{
  inputs,
  cell,
}: let
  inherit (inputs.cicero.packages) cicero-entrypoint cicero webhook-trigger cicero-evaluator-nix;
  inherit (inputs.nixpkgs) lib cacert symlinkJoin closureInfo runCommandNoCC;
  inherit (inputs.n2c.packages.nix2container) buildImage buildLayer;
in {
  # jq < result '.layers | map({size: .size, paths: .paths | map(.path)}) | sort_by(.size) | .[11].paths[]' -r | xargs du -sch
  cicero = let
    # This must include all dependencies used in the image to allow nix builds
    # in the container (Nix won't know about paths otherwise and fail on trying
    # to write read-only data).
    closure = closureInfo {
      rootPaths = {
        inherit (cell.entrypoints) cicero;
        inherit cacert;
      };
    };

    global = runCommandNoCC "global" {} ''
      mkdir -p $out $out/etc
      cp ${closure}/registration $out

      echo 'root:x:0:' > $out/etc/group
      echo 'nixbld:x:30000:nixbld1' > $out/etc/group

      echo 'root:!:0:0::/local:/bin/bash' > $out/etc/passwd
      echo 'nixbld1:!:30001:30000:Nix build user 1:/var/empty:/bin/nologin' >> $out/etc/passwd
    '';

    tmp = runCommandNoCC "tmp" {} ''
      mkdir -p $out/tmp
    '';
  in
    buildImage {
      name = "registry.ci.iog.io/cicero";
      config.Cmd = ["${cell.entrypoints.cicero}/bin/entrypoint"];
      config.Env = lib.mapAttrsToList (n: v: "${n}=${v}") {
        NIX_CONFIG = ''
          sandbox = false
          experimental-features = nix-command flakes
        '';
        PATH = lib.makeBinPath (with inputs.nixpkgs; [
          bashInteractive
          strace
          nix
          coreutils
        ]);
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      };
      maxLayers = 60;
      contents = [
        (symlinkJoin {
          name = "root";
          paths = [cell.entrypoints.cicero inputs.nixpkgs.bashInteractive global];
        })
        tmp
      ];
      perms = [
        {
          path = tmp;
          regex = ".*";
          mode = "0777";
        }
      ];
    };

  webhook-trigger = buildImage {
    name = "registry.ci.iog.io/webhook-trigger";
    config.Cmd = ["${webhook-trigger}/bin/trigger"];
    maxLayers = 4;
  };
}
