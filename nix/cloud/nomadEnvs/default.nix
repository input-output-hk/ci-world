{
  inputs,
  cell,
}: let
  inherit (inputs.data-merge) append merge;
  inherit (inputs.bitte-cells) patroni vector;
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
      ;
  in {
    database = merge (patroni.nomadJob.default (args.prod // {inherit (patroniMods) scaling;})) {
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
