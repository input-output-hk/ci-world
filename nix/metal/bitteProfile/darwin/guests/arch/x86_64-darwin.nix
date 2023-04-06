{config, ...}: let
  cfg = config.services.buildkite-services-darwin;
in {
  services.buildkite-services-darwin = {
    arch = "x86_64-darwin";
    metadata = ["system=x86_64-darwin"];
  };
}
