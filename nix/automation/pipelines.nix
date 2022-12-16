{
  cell,
  inputs,
}: {
  "cicero/deploy" = {
    config,
    lib,
    pkgs,
    ...
  }: {
    command.text = ''
      system=$(nix eval --raw --impure --expr __currentSystem)
      nix run .#"$system".cloud.oci-images.cicero.copyToRegistry \
        --override-input cicero github:input-output-hk/cicero/${config.preset.github.lib.readRevision "GitHub event" "HEAD"}
      nix eval .#"$system".cloud.nomadEnvs.prod.cicero --json | nomad job run -
    '';

    dependencies = with pkgs; [nomad];

    nomad.templates = [
      {
        destination = "/secrets/auth.json";
        data = ''
          {
            "auths": {
              "registry.ci.iog.io": {
                "auth": "{{with secret "kv/data/cicero/docker"}}{{with .Data.data}}{{base64Encode (print .user ":" .password)}}{{end}}{{end}}"
              }
            }
          }
        '';
      }
    ];

    env.REGISTRY_AUTH_FILE = "/secrets/auth.json";

    preset = {
      nix.enable = true;
      github.ci = {
        enable = config.actionRun.facts != {};
        repository = "input-output-hk/cicero";
        revision = config.preset.github.lib.readRevision "GitHub event" "HEAD";
      };
    };

    memory = 1024 * 10;
    nomad.resources.cpu = 2000;
  };

  test-darwin-nix-remote-builders = {
    config,
    pkgs,
    ...
  }: {
    preset.nix.enable = true;

    command.text = ''
      set -x
      nix build --file /local
      cat result
    '';

    nomad = {
      templates = [
        {
          destination = "/local/default.nix";
          data = ''
            let
              nixpkgs = __getFlake github:NixOS/nixpkgs/6107f97012a0c134c5848125b5aa1b149b76d2c9;
              pkgs = nixpkgs.legacyPackages.x86_64-darwin;
            in
              pkgs.runCommand "foo" {} '''
                {
                  echo '{{timestamp}}' # to force a new build
                  uname
                } > $out
              '''
          '';
        }
      ];

      driver = "exec";
    };
  };
}
