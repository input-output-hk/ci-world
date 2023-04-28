{
  config,
  pkgs,
  lib,
  ...
}: {
  nix.settings = let
    post-build-hook = pkgs.writeShellScript "spongix" ''
      set -euf
      IFS=' '
      echo "Uploading to cache: $DRV_PATH $OUT_PATHS"
      exec nix copy --to 'http://${config.cluster.builder}:7745' $DRV_PATH $OUT_PATHS
    '';
  in {
    substituters = lib.mkForce ["http://cache:7745"];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      (lib.fileContents (config.secrets.encryptedRoot + "/nix-public-key-file"))
      (lib.fileContents (config.secrets.encryptedRoot + "/spongix-public-key-file"))
    ];
    http2 = true;
    gc-keep-derivations = true;
    keep-outputs = true;
    min-free-check-interval = 300;
    log-lines = 100;
    warn-dirty = false;
    sandbox-fallback = lib.mkForce true;
    post-build-hook = post-build-hook;
    secret-key-files = config.secrets.install.spongix-secret-key.target;
    narinfo-cache-positive-ttl = 0;
    narinfo-cache-negative-ttl = 0;
  };

  secrets.install.spongix-secret-key = {
    inputType = "binary";
    outputType = "binary";
    source = config.secrets.encryptedRoot + "/spongix-secret-key-file";
    target = "/etc/nix/secret-key";
    script = ''
      chmod 0600 /etc/nix/secret-key
    '';
  };
}
