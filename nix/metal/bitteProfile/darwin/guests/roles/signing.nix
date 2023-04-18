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
    metadata = ["queue=daedalus" "queue=lace"];
    role = "signing";
  };
}
