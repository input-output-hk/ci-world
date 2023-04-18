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
    metadata = ["queue=default" "queue=core-tech"];
    role = "ci";
  };
}
