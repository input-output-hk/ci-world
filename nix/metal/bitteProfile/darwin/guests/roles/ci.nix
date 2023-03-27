{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../modules/basics.nix
    ../modules/hydra-builder.nix
    ../modules/buildkite-agent.nix
  ];
  services.buildkite-services-darwin.metadata = "system=aarch64-darwin,system=x86_64-darwin,queue=default-test,queue=core-tech-test";
  # services.buildkite-services-darwin.metadata = "system=x86_64-darwin,queue=default,queue=core-tech";
}
