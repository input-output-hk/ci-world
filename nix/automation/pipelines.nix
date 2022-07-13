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
    command.text = let
      flakeUrl = lib.escapeShellArg (
        if config.action.facts != {}
        then "github:input-output-hk/ci-world/${inputs.self.rev}"
        else "."
      );
    in ''
      system=$(nix eval --raw --impure --expr __currentSystem)
      nix run ${flakeUrl}#"$system".cloud.oci-images.cicero.copyToRegistry \
        --override-input cicero github:input-output-hk/cicero/${config.preset.github-ci.lib.getRevision "GitHub event" "HEAD"}
      nix eval ${flakeUrl}#"$system".cloud.nomadEnvs.prod.cicero --json | nomad job run -
    '';

    dependencies = with pkgs; [nomad];

    nomad.template = [
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
      github-ci = {
        enable = config.action.facts != {};
        repo = "input-output-hk/cicero";
        sha = config.preset.github-ci.lib.getRevision "GitHub event" "HEAD";
        clone = false;
      };
    };

    memory = 1024 * 10;
    nomad.resources.cpu = 2000;
  };
}
