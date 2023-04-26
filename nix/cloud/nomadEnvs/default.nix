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
  infra = let
    inherit
      (constants.infra)
      # App constants
      
      WALG_S3_PREFIX
      # Job mod constants
      
      patroniMods
      ;
  in {
    database = merge (patroni.nomadCharts.default (args.infra // {inherit (patroniMods) scaling;})) {
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
  };

  prod = let
    inherit
      (constants.prod)
      # Job mod constants
      
      tempoMods
      ;
  in {
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

    postgrest = inputs.cells.perf.jobs.default;
  };

  perf = {
    postgrest = inputs.cells.perf.jobs.default inputs.cells.perf.constants.args.perf;
  };
}
