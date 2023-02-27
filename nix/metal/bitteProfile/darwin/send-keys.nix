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

      "${darwinName}.mmfarm.bitte-world.ziti.json" = {
        encSrc = ../encrypted/darwin/zt/${darwinName}.mmfarm.bitte-world.ziti.json;
        targetDir = "/var/root/ziti/identity";
        preScript = ''
          mkdir -p /var/root/ziti/identity
          chmod 0700 /var/root/ziti/identity
        '';
      };
    };
  };
}
