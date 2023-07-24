{
  config,
  pkgs,
  lib,
  ...
}: {
  nix.settings = let
    r2Cache = "s3://devx?endpoint=fc0e8a9d61fc1f44f378bdc5fdc0f638.r2.cloudflarestorage.com&region=auto";
    r2CacheWritable = "${r2Cache}&secret-key=${config.secrets.install.r2-secret-key.target}&compression=zstd";

    post-build-hook = pkgs.writeShellScript "r2" ''
      set -euf
      IFS=' '
      echo "Uploading to cache: $DRV_PATH $OUT_PATHS"
      exec nix copy --to ${lib.escapeShellArg r2CacheWritable} $DRV_PATH $OUT_PATHS
    '';
  in {
    substituters = lib.mkForce [r2Cache "https://cache.nixos.org"];

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
    secret-key-files = config.secrets.install.r2-secret-key.target;
    narinfo-cache-positive-ttl = 0;
    narinfo-cache-negative-ttl = 0;
  };

  secrets.install = {
    r2-secret-key = rec {
      inputType = "binary";
      outputType = "binary";
      source = config.secrets.encryptedRoot + "/spongix-secret-key-file";
      target = "/etc/nix/secret-key";
      script = ''
        chmod 0600 ${lib.escapeShellArg target}
      '';
    };
    r2-aws = rec {
      inputType = "binary";
      outputType = "binary";
      source = config.secrets.encryptedRoot + "/r2-aws";
      target = "/root/.aws/credentials";
      script = ''
        chmod 0600 ${lib.escapeShellArg target}
      '';
    };
  };
}
