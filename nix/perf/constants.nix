{
  inputs,
  cell,
}: let
  # Metadata
  # -----------------------------------------------------------------------
  baseDomain = "ci.iog.io";
in rec {
  # App Component Import Parameterization
  # -----------------------------------------------------------------------
  args = {
    perf = {
      namespace = "perf";
      domain = "${baseDomain}";
      nodeClass = "perf";
      datacenters = ["eu-central-1"];
    };
  };

  perf = let
    inherit (args.perf) namespace;
  in rec {
    # App constants

    # Job mod constants
  };
}
