{
  inputs,
  cell,
}: let
  inherit (inputs.data-merge) append merge;
  inherit (inputs.bitte-cells) patroni tempo vector;
  inherit (cell) constants;
  inherit (constants) args;
  inherit (cell.library) pp;
in {
  prod = let
    inherit
      (constants.prod)
      # App constants
      
      WALG_S3_PREFIX
      # Job mod constants
      
      patroniMods
      tempoMods
      ;
  in {
    database = merge (patroni.nomadCharts.default (args.prod // {inherit (patroniMods) scaling;})) {
      job.database.constraint = append [
        {
          operator = "distinct_property";
          attribute = "\${attr.platform.aws.placement.availability-zone}";
        }
      ];
      job.database.group.database.task.patroni.resources = {inherit (patroniMods.resources) cpu memory;};
      job.database.group.database.task.patroni.env = {inherit WALG_S3_PREFIX;};
      job.database.group.database.task.backup-walg.env = {inherit WALG_S3_PREFIX;};
    };

    tempo = merge (tempo.nomadCharts.default (args.prod
      // {
        inherit (tempoMods) scaling;

        nodeClass = "test";

        extraTempo = {
          services.tempo = {
            inherit (tempoMods) storageS3Bucket storageS3Endpoint;
          };
        };
      })) {
      job.tempo.group.tempo.task.tempo = {
        env = {
          # DEBUG_SLEEP = 3600;
          # LOG_LEVEL = "debug";
        };
        resources = {inherit (tempoMods.resources) cpu memory;};
      };
    };

    cicero = import ./cicero {
      inherit inputs cell;
      inherit (constants.args.prod) domain namespace;
    };

    webhooks = import ./webhooks {
      inherit inputs cell;
      inherit (constants.args.prod) domain namespace;
    };
  };
}
