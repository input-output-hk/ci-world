{
  inputs,
  cell,
}: let
  inherit (inputs.nixpkgs) lib;

  mkCicero = f:
    inputs.nixpkgs.writeShellApplication (f {
      name = "entrypoint";
      runtimeInputs = with inputs.cicero.inputs.nixpkgs.legacyPackages.${inputs.nixpkgs.system}; [
        inputs.cicero.packages.cicero
        inputs.cicero.packages.cicero-evaluator-nix
        nix
        bashInteractive
        coreutils
        gitMinimal
        dbmate
        vault
      ];
      text = ''
        # dbmate doesn't use pgx yet, so we have to remove this string
        # Error: unable to connect to database: pq: unrecognized configuration parameter "target_session_attrs"
        dbmate \
          --url "''${DATABASE_URL//?target_session_attrs=read-write/}" \
          --migrations-dir ${inputs.cicero}/db/migrations \
          --no-dump-schema \
          --wait \
          up

        if [[ -v VAULT_TOKEN ]]; then
          NOMAD_TOKEN=$(vault read -field secret_id nomad/creds/cicero)
          export NOMAD_TOKEN
        else
          echo 'No VAULT_TOKEN set, skipped obtaining a Nomad token'
        fi

        set -x
        exec cicero start "$@"
      '';
    });
in {
  cicero = mkCicero lib.id;

  cicero-oci = mkCicero (
    args:
      args
      // {
        runtimeInputs = with inputs.nixpkgs;
          args.runtimeInputs
          ++ [
            netcat
            shadow
          ];
        text = ''
          set -x

          nix-store --load-db < /registration

          echo "nameserver ''${NAMESERVER:-172.17.0.1}" > /etc/resolv.conf

          if [[ -v NAMESERVER ]]; then
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
          ${args.text}
        '';
      }
  );
}
