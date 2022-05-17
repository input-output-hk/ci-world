{
  inputs,
  cell,
}: let
  inherit (inputs.nixpkgs) writeShellApplication cacert lib;
  inherit (inputs.cicero.packages) cicero cicero-evaluator-nix;
in {
  cicero = writeShellApplication {
    name = "entrypoint";
    runtimeInputs = with inputs.nixpkgs; [
      # cicero
      # cicero-evaluator-nix
      # nix
      # bashInteractive
      # coreutils
      # gitMinimal
      # dbmate
      # vault-bin
      # netcat
      # shadow
      coreutils
      nix
    ];
    text = ''
      set -x

      id
      env
      nix-store --load-db < /registration
      nix build github:input-output-hk/tullia
    '';
  };
}
