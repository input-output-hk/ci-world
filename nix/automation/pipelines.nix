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
        nix flake show ${flakeUrl args} --allow-import-from-derivation --override-input flake-arch github:input-output-hk/flake-arch/x86_64-linux
        nix flake check ${flakeUrl args} --allow-import-from-derivation --override-input flake-arch github:input-output-hk/flake-arch/x86_64-linux
      '';

      preset.github-ci.clone = true;
      memory = 1024 * 24;
      nomad.resources.cpu = 9000;
    };
  };
}
