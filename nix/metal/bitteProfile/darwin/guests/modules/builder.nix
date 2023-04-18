{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (sshKeyLib) allKeysFrom devOps csl-developers remoteBuilderKeys;

  sshKeyLib = import (inputs.ops-lib + "/overlays/ssh-keys.nix") lib;
  sshKeys =
    allKeysFrom (devOps // {inherit (csl-developers) angerman;})
    ++ allKeysFrom remoteBuilderKeys;

  environment = lib.concatStringsSep " " [
    "NIX_REMOTE=daemon"
    "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
  ];
in {
  users.knownUsers = ["builder"];
  users.users.builder = {
    uid = 502;
    gid = 20; # staff
    description = "Hydra";
    home = "/Users/builder";
    shell = "/bin/bash";
  };

  nix.settings.trusted-users = ["root" "builder"];

  # Create a ~/.bashrc containing source /etc/profile
  # (bash doesn't source the ones in /etc for non-interactive
  # shells and that breaks everything nix)
  system.activationScripts.postActivation.text = ''
    mkdir -p /Users/builder
    echo "source /etc/profile" > /Users/builder/.bashrc
    chown builder: /Users/builder/.bashrc
    dscl . -list /Groups | grep -q com.apple.access_ssh-disabled || dseditgroup -o edit -a builder -t user com.apple.access_ssh
  '';

  # Guest builder ssh keys
  environment.etc."per-user/builder/ssh/authorized_keys".text =
    lib.concatMapStringsSep "\n" (key: ''command="${environment} ${config.nix.package}/bin/nix-store --serve --write" ${key}'') sshKeys + "\n";
}
