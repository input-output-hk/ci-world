({
  config,
  inputs,
  lib,
  ...
}: let
  akh = config.programs.auth-keys-hub;
  target = "${akh.dataDir}/github-token";
in {
  imports = [inputs.auth-keys-hub.nixosModules.auth-keys-hub];

  secrets.install.github-token = {
    inputType = "binary";
    outputType = "binary";
    source = config.secrets.encryptedRoot + "/github-token";
    inherit target;
    script = ''
      chown ${akh.user}:${akh.group} ${target}
      chmod 0600 ${target}
    '';
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = lib.mkForce [];

  programs.auth-keys-hub = {
    enable = true;
    github = {
      teams = ["input-output-hk/devops"];
      tokenFile = target;
    };
  };
})
