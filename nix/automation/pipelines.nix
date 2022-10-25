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
}
