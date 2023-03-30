{config, ...}: let
  cfg = config.services.buildkite-services-darwin;
in {
  services.buildkite-services-darwin = {
    arch = "aarch64-darwin";
    metadata = [
      "system=aarch64-darwin"
      "system=x86_64-darwin"

      # An extra queue to disambiguate during pre-prod testing
      "queue=${cfg.role}-${cfg.arch}-test"
    ];
  };

  nix.extraOptions = ''
    system = aarch64-darwin
    extra-platforms = aarch64-darwin x86_64-darwin
  '';
}
