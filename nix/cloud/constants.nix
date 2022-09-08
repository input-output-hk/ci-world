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
    prod = {
      namespace = "prod";
      domain = "${baseDomain}";
      nodeClass = "prod";
      datacenters = ["eu-central-1"];
    };
  };

  prod = let
    inherit (args.prod) namespace;
  in rec {
    # App constants
    WALG_S3_PREFIX = "s3://iohk-ci-bitte/backups/${namespace}/walg";

    # Job mod constants
    patroniMods.scaling = 3;
    patroniMods.resources.cpu = 12000;
    patroniMods.resources.memory = 16 * 1024;
    tempoMods.scaling = 1;
    tempoMods.resources.cpu = 3000;
    tempoMods.resources.memory = 3 * 1024;
    tempoMods.storageS3Bucket = "iohk-ci-tempo";
    tempoMods.storageS3Endpoint = "s3.eu-central-1.amazonaws.com";
  };
}
