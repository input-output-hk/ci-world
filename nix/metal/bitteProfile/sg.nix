{
  terralib,
  lib,
}: config: let
  inherit (terralib) cidrsOf;
  inherit (config.cluster.vpc) subnets;
  awsAsgVpcs = terralib.aws.asgVpcs config.cluster;

  global = ["0.0.0.0/0"];
  internal = [config.cluster.vpc.cidr] ++ (lib.forEach awsAsgVpcs (vpc: vpc.cidr));
in {
  wg = {
    port = 51820;
    protocols = ["udp"];
    cidrs = global;
  };
}
