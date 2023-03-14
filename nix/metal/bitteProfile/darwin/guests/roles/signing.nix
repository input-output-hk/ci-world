{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../modules/basics.nix
    ../modules/buildkite-agent.nix
  ];
  services.buildkite-services-darwin.metadata = "system=aarch64-darwin,queue=daedalus-test,queue=lace-test";
  # services.buildkite-services-darwin.metadata = "system=x86_64-darwin,queue=daedalus,queue=lace";
}
