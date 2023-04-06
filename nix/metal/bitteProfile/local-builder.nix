{
  config,
  pkgs,
  lib,
  ...
}: {
  profiles.auxiliaries.builder.enable = false;

  nix = let
    supportedFeatures = ["big-parallel" "benchmark"];
  in {
    buildMachines = let
      mkDarwinBuilder = name: maxJobs: speedFactor: systems: mandatoryFeatures: extraConfig: {
        inherit maxJobs speedFactor systems mandatoryFeatures;
        hostName = name;
        sshKey = "/etc/nix/darwin-builder-key-ng";
        sshUser = "builder";
        inherit supportedFeatures;
      } // extraConfig;
    in [
      # Builders
      (mkDarwinBuilder "mm1-builder" 1 1 ["x86_64-darwin"] [] {})
      (mkDarwinBuilder "mm2-builder" 1 1 ["x86_64-darwin"] [] {})
      (mkDarwinBuilder "mm-intel3-builder" 4 4 ["x86_64-darwin"] [] {})
      # (mkDarwinBuilder "mm-intel4-builder" 4 4 ["x86_64-darwin"] [] {})
      (mkDarwinBuilder "ms-arm1-builder" 4 4 ["x86_64-darwin" "aarch64-darwin"] [] {})
      (mkDarwinBuilder "ms-arm2-builder" 4 4 ["x86_64-darwin" "aarch64-darwin"] [] {})

      # Signing
      (mkDarwinBuilder "mm1-signing" 1 1 ["x86_64-darwin"] ["signing"] {})
      (mkDarwinBuilder "mm2-signing" 1 1 ["x86_64-darwin"] ["signing"] {})
      # (mkDarwinBuilder "mm-intel3-signing" 4 4 ["x86_64-darwin"] ["signing"] {})
      (mkDarwinBuilder "mm-intel4-signing" 4 4 ["x86_64-darwin"] ["signing"] {})
      (mkDarwinBuilder "ms-arm1-signing" 4 4 ["x86_64-darwin" "aarch64-darwin"] ["signing"] {})
      (mkDarwinBuilder "ms-arm2-signing" 4 4 ["x86_64-darwin" "aarch64-darwin"] ["signing"] {})
    ];

    distributedBuilds = true;

    settings = {
      # Even if KVM is not supported; better to run slow than to fail
      system-features = supportedFeatures ++ ["kvm"];

      experimental-features = ["ca-derivations"];
      trusted-users = ["root" "builder"];
      builders = "@/etc/nix/machines";

      # Constrain Linux builds to 4 hrs
      timeout = 14400;

      connect-timeout = 10;
    };
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
      # Builders
      (mkDarwinBuilderSsh "mm1-builder" "10.10.0.1")
      (mkDarwinBuilderSsh "mm2-builder" "10.10.0.2")
      (mkDarwinBuilderSsh "mm-intel3-builder" "10.10.0.3")
      (mkDarwinBuilderSsh "mm-intel4-builder" "10.10.0.4")
      (mkDarwinBuilderSsh "ms-arm1-builder" "10.10.0.51")
      (mkDarwinBuilderSsh "ms-arm2-builder" "10.10.0.52")

      # Signing
      (mkDarwinBuilderSsh "mm1-signing" "10.10.0.101")
      (mkDarwinBuilderSsh "mm2-signing" "10.10.0.102")
      (mkDarwinBuilderSsh "mm-intel3-signing" "10.10.0.103")
      (mkDarwinBuilderSsh "mm-intel4-signing" "10.10.0.104")
      (mkDarwinBuilderSsh "ms-arm1-signing" "10.10.0.151")
      (mkDarwinBuilderSsh "ms-arm2-signing" "10.10.0.152")
    ];

  secrets.install.darwin-secret-key = {
    inputType = "binary";
    outputType = "binary";
    source = config.secrets.encryptedRoot + "/darwin-builder-key-ng";
    target = "/etc/nix/darwin-builder-key-ng";
    script = ''
      chmod 0600 /etc/nix/darwin-builder-key-ng
    '';
  };
}
