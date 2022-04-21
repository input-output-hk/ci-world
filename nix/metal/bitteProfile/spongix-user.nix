{
  config,
  pkgs,
  lib,
  ...
}: {
  nix.binaryCaches = lib.mkForce ["http://cache:7745"];
  nix.binaryCachePublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    (lib.fileContents (config.secrets.encryptedRoot + "/nix-public-key-file"))
    (lib.fileContents (config.secrets.encryptedRoot + "/spongix-public-key-file"))
  ];
  nix.extraOptions = let
    post-build-hook = pkgs.writeShellScript "spongix" ''
      set -euf
      export IFS=' '
      echo "Uploading to cache: $OUT_PATHS"
      exec nix copy --to 'http://${config.cluster.builder}:7745' $OUT_PATHS
    '';
  in ''
    http2 = true
    gc-keep-derivations = true
    keep-outputs = true
    min-free-check-interval = 300
    log-lines = 100
    warn-dirty = false
    fallback = true
    post-build-hook = ${post-build-hook}
    secret-key-files = ${config.secrets.install.spongix-secret-key.target}
    narinfo-cache-positive-ttl = 0
    narinfo-cache-negative-ttl = 0
  '';

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
