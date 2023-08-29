{inputs, ...}: {
  imports = [
    inputs.bitte.profiles.common
    inputs.bitte.profiles.consul-client
    inputs.bitte.profiles.vault-cache
    inputs.bitte.profiles.auxiliaries-builder
  ];
  nix.settings.system-features = ["big-parallel"];
}
