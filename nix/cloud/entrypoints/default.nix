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
      cicero
      cicero-evaluator-nix
      nix
      bashInteractive
      coreutils
      gitMinimal
      dbmate
      vault-bin
      netcat
      shadow
    ];
    text = ''
      set -x

      nix-store --load-db < /registration

      echo "nameserver ''${NAMESERVER:-172.17.0.1}" > /etc/resolv.conf

      if [ -n "''${NAMESERVER:-}" ]; then
        echo "nameserver ''${NAMESERVER:-}" > /etc/resolv.conf
      else
        defaultNameservers=(172.17.0.1 127.0.0.1 1.1.1.1)

        for ns in "''${defaultNameservers[@]}"; do
          if nc -z -w 3 "$ns" 53; then
            echo "nameserver ''${NAMESERVER:-$ns}" > /etc/resolv.conf
            break
          fi
        done
      fi

      set +x
      # dbmate doesn't use pgx yet, so we have to remove this string
      # Error: unable to connect to database: pq: unrecognized configuration parameter "target_session_attrs"
      dbmate \
        --url "''${DATABASE_URL//?target_session_attrs=read-write/}" \
        --migrations-dir ${inputs.cicero}/db/migrations \
        --no-dump-schema \
        --wait \
        up

      if [ -n "''${VAULT_TOKEN:-}" ]; then
        NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/cicero)"
        export NOMAD_TOKEN
      else
        echo "No VAULT_TOKEN set, skipped obtaining a Nomad token"
      fi
      set -x

      exec cicero start "$@"
    '';
  };
}
