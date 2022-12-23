{
  config,
  pkgs,
  lib,
  ...
}: {
  profiles.auxiliaries.builder.enable = false;

  nix = {
    buildMachines = let
      mkDarwinBuilder = name: mandatoryFeatures: {
        inherit mandatoryFeatures;
        hostName = name;
        maxJobs = 4;
        speedFactor = 1;
        sshKey = "/etc/nix/darwin-builder-key";
        sshUser = "builder";
        systems = ["x86_64-darwin"];
        supportedFeatures = ["big-parallel"];
      };
    in [
      (mkDarwinBuilder "mm1-builder" [])
      (mkDarwinBuilder "mm2-builder" [])
      (mkDarwinBuilder "mm1-signer" ["signer"])
      (mkDarwinBuilder "mm2-signer" ["signer"])
    ];

    distributedBuilds = true;

    trustedUsers = ["root" "builder"];

    extraOptions = ''
      builders = @/etc/nix/machines

      # Constrain Linux builds to 4 hrs
      timeout = 14400

      connect-timeout = 10
    '';
  };

  programs.ssh.extraConfig = let
    mkDarwinBuilderSsh = name: ip: ''
      Host ${name}
        Hostname ${ip}
        Port 22
        PubkeyAcceptedKeyTypes ecdsa-sha2-nistp256,ssh-ed25519,ssh-rsa
        IdentityFile /etc/nix/darwin-builder-key
        StrictHostKeyChecking accept-new
        ControlMaster auto
        ControlPath ~/.ssh/master-%r@%n:%p
        ControlPersist 1m
    '';
  in
    builtins.concatStringsSep "\n" [
      (mkDarwinBuilderSsh "mm1-builder" "10.10.0.1")
      (mkDarwinBuilderSsh "mm2-builder" "10.10.0.2")
      (mkDarwinBuilderSsh "mm1-signer" "10.10.0.101")
      (mkDarwinBuilderSsh "mm2-signer" "10.10.0.102")
    ];

  secrets.install.darwin-secret-key = {
    inputType = "binary";
    outputType = "binary";
    source = config.secrets.encryptedRoot + "/darwin-builder-key";
    target = "/etc/nix/darwin-builder-key";
    script = ''
      chmod 0600 /etc/nix/darwin-builder-key
    '';
  };
}
