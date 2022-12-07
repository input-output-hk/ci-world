{
  inputs,
  cell,
}: let
  inherit (inputs) capsules bitte-cells bitte deploy-rs nixpkgs;
  inherit (inputs.std) std;
  inherit (inputs.std.lib) dev;

  # FIXME: this is a work around just to get access
  # to 'awsAutoScalingGroups'
  # TODO: std ize bitte properly to make this interface nicer
  bitte' = inputs.bitte.lib.mkBitteStack {
    inherit inputs;
    inherit (inputs) self;
    domain = "ci.iog.io";
    bitteProfile = inputs.cells.metal.bitteProfile.default;
    hydrationProfile = inputs.cells.cloud.hydrationProfile.default;
    deploySshKey = "not-a-key";
  };

  ciWorld = {
    extraModulesPath,
    pkgs,
    ...
  }: {
    name = nixpkgs.lib.mkForce "CI World";
    imports = [
      std.devshellProfiles.default
      bitte.devshellModule
    ];
    bitte = {
      domain = "ci.iog.io";
      cluster = "ci-world";
      namespace = "prod";
      provider = "AWS";
      cert = null;
      aws_profile = "ci";
      aws_region = "eu-central-1";
      aws_autoscaling_groups =
        bitte'.clusters.ci-world._proto.config.cluster.awsAutoScalingGroups;
    };
  };
in {
  dev = dev.mkShell {
    imports = [
      ciWorld
      capsules.base
      capsules.cloud
    ];
  };
  ops = dev.mkShell {
    imports = [
      ciWorld
      capsules.base
      capsules.cloud
      capsules.hooks
      capsules.metal
      capsules.integrations
      capsules.tools
      bitte-cells.patroni.devshellProfiles.default
    ];
    commands = let
      withCategory = category: attrset: attrset // {inherit category;};
      ciWorld = withCategory "ci-world";
    in
      with nixpkgs; [
        (ciWorld {package = deploy-rs.defaultPackage;})
        (ciWorld {package = httpie;})
      ];
  };
}
