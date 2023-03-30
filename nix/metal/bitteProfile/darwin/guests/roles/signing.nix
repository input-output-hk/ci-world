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

  services.buildkite-services-darwin = {
    # When ready to switch to prod:
    # metadata = ["queue=daedalus" "queue=lace"];
    metadata = ["queue=daedalus-test" "queue=lace-test"];

    role = "signing";
  };
}
