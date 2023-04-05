darwinName: {
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  inherit (types) attrsOf int listOf oneOf package path str submodule;

  cfg = config.services.send-keys;

  darwinConfigKeys = {
    options = {
      keys = mkOption {
        type = attrsOf (submodule key);
        default = {};
      };
    };
  };

  key = {name, ...}: {
    # Note that changes to these options may require changes to the bash script
    # at `nix/metal/packages/darwin/darwin.sh` which utilizes this module config.
    options = {
      filename = mkOption {
        type = str;
        default = name;
        description = ''
          Target filename; will take the attr name by default.
          Will be placed at `targetDir` dir on the remote darwin machine.
        '';
      };

      encSrc = mkOption {
        type = path;
        default = null;
        description = ''
          Source encrypted file path, relative to calling modules directory.

          NOTE: As this is a nix path, these key files need to be committed
          to be deployable!
        '';
      };

      targetDir = mkOption {
        type = str;
        default = null;
        description = ''
          Destination dir for `filename` on the remote darwin machine.
        '';
      };

      mode = mkOption {
        type = str;
        default = "0600";
        description = ''
          File mode for the destination file on the remote darwin machine.
        '';
      };

      owner = mkOption {
        type = str;
        default = "root:wheel";
        description = ''
          Ownership for the destination file on the remote darwin machine.
        '';
      };

      preScript = mkOption {
        type = str;
        default = "";
        description = ''
          Shell script which will be run prior to key deployment.

          NOTE: binaries available for scripts are determined by remote
          system pkgs and environment.  Try adding a path spec or
          additional packages to the remote if needed.
        '';
      };

      postScript = mkOption {
        type = str;
        default = "";
        description = ''
          Shell script which will be run after key deployment.

          NOTE: binaries available for scripts are determined by remote
          system pkgs and environment.  Try adding a path spec or
          additional packages to the remote if needed.
        '';
      };
    };
  };
in {
  options.services.darwin-send-keys = mkOption {
    type = attrsOf (submodule darwinConfigKeys);
    default = {};
  };

  config = {
    services.darwin-send-keys.${darwinName}.keys = {
      "wireguard-private.key" = {
        encSrc = ../encrypted/darwin/wg/${darwinName}-private;
        targetDir = "/var/root/.keys";
        preScript = ''
          mkdir -p /var/root/.keys
          chmod 0700 /var/root/.keys
        '';
      };

      "${darwinName}.darwin.bitte-world.ziti.json" = {
        encSrc = ../encrypted/darwin/zt/${darwinName}.darwin.ci-world.ziti.enc.json;
        targetDir = "/var/root/ziti/identity";
        preScript = ''
          mkdir -p /var/root/ziti/identity
          chmod 0700 /var/root/ziti/identity
        '';
      };

      # Keys to be shared with guests can't go directly to the destination as symlinked files won't get shared over virtiofs.
      # So place them in a common dir to be copied to the virtiofs share on system activation.
      # Virtiofs shares require o+r object perms as uid:gid doesn't get passed and the guest sees ownership as unknown user and group.
      "netrc" = {
        encSrc = ../encrypted/darwin/common/netrc.enc;
        targetDir = "/etc/decrypted/guests";
        mode = "0644";
        preScript = "mkdir -p /etc/decrypted/guests";
      };

      # Buildkite
      "buildkite_token" = {
        encSrc = ../encrypted/buildkite/buildkite_token;
        targetDir = "/etc/decrypted/guests/buildkite";
        mode = "0644";
        preScript = "mkdir -p /etc/decrypted/guests/buildkite";
      };

      "buildkite_aws_creds" = {
        encSrc = ../encrypted/buildkite/buildkite-hook;
        targetDir = "/etc/decrypted/guests/buildkite";
        mode = "0644";
        preScript = "mkdir -p /etc/decrypted/guests/buildkite";
      };

      "buildkite-ssh-iohk-devops-private" = {
        encSrc = ../encrypted/buildkite/buildkite-iohk-devops-ssh;
        targetDir = "/etc/decrypted/guests/buildkite";
        preScript = "mkdir -p /etc/decrypted/guests/buildkite";

        postScript = ''
          cd /etc/decrypted/guests/buildkite
          ssh-keygen -y -f buildkite-ssh-iohk-devops-private > buildkite-ssh-iohk-devops-public
          chmod 0644 buildkite-ssh-iohk-devops-private
        '';
      };

      "catalyst-env.sh" = {
        encSrc = ../encrypted/buildkite/catalyst-env.sh;
        targetDir = "/etc/decrypted/guests/buildkite";
        mode = "0644";
        preScript = "mkdir -p /etc/decrypted/guests/buildkite";
      };

      "catalyst-sentry.properties" = {
        encSrc = ../encrypted/buildkite/catalyst-sentry.properties;
        targetDir = "/etc/decrypted/guests/buildkite";
        mode = "0644";
        preScript = "mkdir -p /etc/decrypted/guests/buildkite";
      };

      # Ssh
      "guest-ci-ssh_host_ed25519_key" = {
        encSrc = ../encrypted/darwin/hosts/${darwinName}/ci/ssh/ssh_host_ed25519_key.enc;
        filename = "ssh_host_ed25519_key";
        targetDir = "/etc/decrypted/guests/ci/ssh";
        preScript = "mkdir -p /etc/decrypted/guests/ci/ssh";

        postScript = ''
          cd /etc/decrypted/guests/ci/ssh
          ssh-keygen -y -f ssh_host_ed25519_key > ssh_host_ed25519_key.pub
          chmod 0644 ssh_host_ed25519_key
        '';
      };

      "guest-ci-ssh_host_ecdsa_key" = {
        encSrc = ../encrypted/darwin/hosts/${darwinName}/ci/ssh/ssh_host_ecdsa_key.enc;
        filename = "ssh_host_ecdsa_key";
        targetDir = "/etc/decrypted/guests/ci/ssh";
        preScript = "mkdir -p /etc/decrypted/guests/ci/ssh";

        postScript = ''
          cd /etc/decrypted/guests/ci/ssh
          ssh-keygen -y -f ssh_host_ecdsa_key > ssh_host_ecdsa_key.pub
          chmod 0644 ssh_host_ecdsa_key
        '';
      };

      "guest-ci-ssh_host_rsa_key" = {
        encSrc = ../encrypted/darwin/hosts/${darwinName}/ci/ssh/ssh_host_rsa_key.enc;
        filename = "ssh_host_rsa_key";
        targetDir = "/etc/decrypted/guests/ci/ssh";
        preScript = "mkdir -p /etc/decrypted/guests/ci/ssh";

        postScript = ''
          cd /etc/decrypted/guests/ci/ssh
          ssh-keygen -y -f ssh_host_rsa_key > ssh_host_rsa_key.pub
          chmod 0644 ssh_host_rsa_key
        '';
      };

      "guest-signing-ssh_host_ed25519_key" = {
        encSrc = ../encrypted/darwin/hosts/${darwinName}/signing/ssh/ssh_host_ed25519_key.enc;
        filename = "ssh_host_ed25519_key";
        targetDir = "/etc/decrypted/guests/signing/ssh";
        preScript = "mkdir -p /etc/decrypted/guests/signing/ssh";

        postScript = ''
          cd /etc/decrypted/guests/signing/ssh
          ssh-keygen -y -f ssh_host_ed25519_key > ssh_host_ed25519_key.pub
          chmod 0644 ssh_host_ed25519_key
        '';
      };

      "guest-signing-ssh_host_ecdsa_key" = {
        encSrc = ../encrypted/darwin/hosts/${darwinName}/signing/ssh/ssh_host_ecdsa_key.enc;
        filename = "ssh_host_ecdsa_key";
        targetDir = "/etc/decrypted/guests/signing/ssh";
        preScript = "mkdir -p /etc/decrypted/guests/signing/ssh";

        postScript = ''
          cd /etc/decrypted/guests/signing/ssh
          ssh-keygen -y -f ssh_host_ecdsa_key > ssh_host_ecdsa_key.pub
          chmod 0644 ssh_host_ecdsa_key
        '';
      };

      "guest-signing-ssh_host_rsa_key" = {
        encSrc = ../encrypted/darwin/hosts/${darwinName}/signing/ssh/ssh_host_rsa_key.enc;
        filename = "ssh_host_rsa_key";
        targetDir = "/etc/decrypted/guests/signing/ssh";
        preScript = "mkdir -p /etc/decrypted/guests/signing/ssh";

        postScript = ''
          cd /etc/decrypted/guests/signing/ssh
          ssh-keygen -y -f ssh_host_rsa_key > ssh_host_rsa_key.pub
          chmod 0644 ssh_host_rsa_key
        '';
      };
    };
  };
}
