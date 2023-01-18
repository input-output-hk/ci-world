{
  inputs,
  cell,
}: let
  # Since dashboards will exist as either JSON already, or will
  # be converted to JSON from Nix (ex: Grafonnix), dashboard attrs
  # are expected to have values of JSON strings.
  importAsJson = file: builtins.readFile file;
  # importGrafonnixToJson = ...;
in {
  ci-world-spongix = importAsJson ./dashboards/spongix.json;
  ci-world-mac-mini-zfs = importAsJson ./dashboards/mac-mini-zfs.json;
  ci-world-node-exporter = importAsJson ./dashboards/node-exporter.json;

  # Upstream dashboards can be imported here, instead of directly
  # imported in the hydrationProfile.  This will allow easier
  # re-export of repo related dashboards which might have downstream
  # re-use.
  # inherit (inputs.X.Y.dashboards)
  # ;
}
