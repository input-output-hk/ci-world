{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../modules/basics.nix
    ../modules/builder.nix
    ../modules/buildkite-agent.nix
  ];

  services.buildkite-services-darwin = {
    # When ready to switch to prod:
    # metadata = ["queue=default" "queue=core-tech"];
    metadata = ["queue=default-test" "queue=core-tech-test"];

    role = "ci";
  };
}
