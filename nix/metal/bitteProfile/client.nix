{
  pkgs,
  lib,
  self,
  ...
}: {
  profiles.auxiliaries.builder.remoteBuilder.buildMachine.supportedFeatures = ["big-parallel"];

  services.nomad.client.chroot_env =
    lib.mkForce {"/etc/passwd" = "/etc/passwd";};

  systemd.services.nomad.serviceConfig = {
    JobTimeoutSec = "600s";
    JobRunningTimeoutSec = "600s";
  };
}
