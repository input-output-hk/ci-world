{
  cell,
  inputs,
}: let
  common = {
    config,
    lib,
    ...
  }: {
    preset = {
      nix.enable = true;
      github-ci = __mapAttrs (_: lib.mkDefault) {
        enable = config.action.facts != {};
        repo = "input-output-hk/ci-world";
        sha = config.preset.github-ci.lib.getRevision "GitHub event" "HEAD";
        clone = false;
      };
    };
  };

  flakeUrl = {
    config,
    lib,
    ...
  }:
    lib.escapeShellArg (
      if config.action.facts != {}
      then "github:input-output-hk/ci-world/${inputs.self.rev}"
      else "."
    );
in {
  "ci/build" = args: {
    imports = [common];

    config = {
      command.text = ''
        echo "Running flake check on ${flakeUrl args}"
        nix flake check --allow-import-from-derivation ${flakeUrl args}
      '';

      preset.github-ci.clone = true;
      memory = 1024 * 24;
      nomad.resources.cpu = 9000;
    };
  };
}
