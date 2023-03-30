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

  system.activationScripts.postActivation.text = ''
    # Ensure Rosetta is installed for x86_64 emulation on apple silicon
    printf "checking for rosetta... "
    if ! [ $(/usr/bin/pgrep oahd) ]; then
      echo "installing"
      softwareupdate --install-rosetta --agree-to-license || true
    else
      echo "already installed"
    fi
  '';

  # Clean up generated AOT x86_64 emulation byproduct files
  launchd.daemons.cleanup-rosetta-cache = {
    script = ''
      /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -P -minsize 0 /System/Volumes/Data/private/var/db/oah
    '';

    serviceConfig = {
      # Run every hour at the 24th minute
      StartCalendarInterval = [{Minute = 24;}];
    };
  };
}
