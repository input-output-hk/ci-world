{
  cell,
  inputs,
}: {
  "cicero/deploy" = {
    config,
    lib,
    pkgs,
    ...
  }: {
    preset.nix.enable = true;

    command.text = ''
      cd "$(git rev-parse --show-toplevel)"
      set -x

      # Set up temporary files for some secrets we'll need.
      trap 'rm -rf "$basic" "$netrc"' EXIT
      basic=$(mktemp)
      netrc=$(mktemp)

      # Decrypt the HTTP basic auth credentials and put them in a netrc file for Nix.
      sops --decrypt --output "$basic" nix/metal/bitteProfile/encrypted/basic-auth
      # Adapt this hacky snippet when the secret is changed.
      cat > "$netrc" <<EOF
      machine  cache.iog.io
      login    $(head -n 1 "$basic" | cut -d \; -f 1 | cut -d : -f 2 | tr -d ' ')
      password $(head -n 1 "$basic" | cut -d \; -f 2 | cut -d : -f 2 | tr -d ' ')
      EOF

      # We need to interpolate the system into the attribute path
      # as std does not provide the entrypoint in an output path
      # that is convenient to use from the Nix CLI.
      system=$(nix eval --raw --impure --expr __currentSystem)

      # Build the required packages so we can run transformers and copy them to the cache.
      readarray -t installables < <(
        # We can rely on word splitting because nix store paths do not contain spaces.
        #shellcheck disable=SC2046
        nix build --no-link --print-out-paths $(
          nix eval .#"$system".cloud.nomadEnvs.prod.cicero.job.cicero.group.cicero.task.cicero.config.nix_installables \
            --apply 'map (p: p.drvPath)' --json \
          | jq --raw-output '.[]'
        )
      )

      # Copy the required packages to the cache so that they will be available for the job.
      nix copy --to https://cache.iog.io --netrc-file "$netrc" "''${installables[@]}"

      # Evaluate the nomad job (as HCL-JSON).
      job=$(nix eval .#"$system".cloud.nomadEnvs.prod.cicero --json)

      # Canonicalize the job (convert to API JSON) and wrap it for transformers.
      # Those are run when Cicero deploys itself and we need to run them as well
      # as we do not want any difference between that deployment and this one.
      # Most notably we want to get the darwin nix remote builders configured.
      job=$(
        <<< "$job" \
        nomad job run -output - \
        | jq '{job: .Job}'
      )
      for installable in "''${installables[@]}"; do
        if [[ "$installable" = /nix/store/*-transform-* ]]; then
          #shellcheck disable=SC2211
          job=$(<<< "$job" "$installable"/bin/transform-*)
        fi
      done
      # Unwrap the job from the dummy action definition.
      job=$(<<< "$job" jq .job)

      # Finally deploy to Nomad.
      nomad job run -json - <<< "$job"
    '';

    dependencies = with inputs.bitte.legacyPackages; [
      nomad
      sops
      jq
    ];

    nsjail = {
      bindmount = {
        ro = ["/etc/nix/netrc"];
        rw = [
          "/nix"
          ''"$XDG_DATA_HOME"/nix/trusted-settings.json''
          ''"$XDG_CACHE_HOME"/nix''
        ];
      };

      flags.env = [
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "NOMAD_ADDR"
        "NOMAD_TOKEN"
        "XDG_DATA_HOME"
        "XDG_CACHE_HOME"
      ];
    };

    memory = 0;
  };

  test-darwin-nix-remote-builders = {
    config,
    pkgs,
    ...
  }: {
    preset.nix.enable = true;

    command.text = ''
      set -x

      ls -la /local/home/.config/nix || true
      cat /local/home/.config/nix/machines || true

      # NIX_SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/local/home/known_hosts"
      # export NIX_SSHOPTS
      # nix store ping --store ssh://builder@10.10.0.1?ssh-key=/secrets/id_buildfarm
      # nix store ping --store ssh://builder@10.10.0.2?ssh-key=/secrets/id_buildfarm
      # nix store ping --store ssh://builder@10.10.0.3?ssh-key=/secrets/id_buildfarm
      # nix store ping --store ssh://builder@10.10.0.51?ssh-key=/secrets/id_buildfarm
      # nix store ping --store ssh://builder@10.10.0.52?ssh-key=/secrets/id_buildfarm

      nix show-config

      # shellcheck disable=SC2016
      nix build --expr 'let nixpkgs = __getFlake github:NixOS/nixpkgs/6107f97012a0c134c5848125b5aa1b149b76d2c9; pkgs = nixpkgs.legacyPackages.aarch64-linux; in pkgs.runCommand "foo" {} "/bin/hostname > $out"' -vvvvv || true

      nix build --file /local/x86_64
      cat result

      nix build --file /local/aarch64
      cat result
    '';

    nomad = {
      templates = [
        {
          destination = "/local/x86_64/default.nix";
          data = ''
            let
              nixpkgs = __getFlake github:NixOS/nixpkgs/6107f97012a0c134c5848125b5aa1b149b76d2c9;
              pkgs = nixpkgs.legacyPackages.x86_64-darwin;
            in
              pkgs.runCommand "foo" {} '''
                {
                  echo '{{timestamp}}' # to force a new build
                  uname
                } > $out
              '''
          '';
        }
        {
          destination = "/local/aarch64/default.nix";
          data = ''
            let
              nixpkgs = __getFlake github:NixOS/nixpkgs/6107f97012a0c134c5848125b5aa1b149b76d2c9;
              pkgs = nixpkgs.legacyPackages.aarch64-darwin;
            in
              pkgs.runCommand "foo" {} '''
                {
                  echo '{{timestamp}}' # to force a new build
                  uname
                } > $out
              '''
          '';
        }
      ];

      driver = config.actionRun.facts.trigger.value."ci-world/test-darwin-nix-remote-builders";
    };
  };

  test-cicero-public-bucket = {pkgs, ...}: {
    preset.nix.enable = true;

    command.text = ''
      set -x
      sleep 15s # wait for AWS creds to become usable

      nix build --file "$NOMAD_TASK_DIR"
      nix store copy-log ./result --to 's3://cicero-public?region=eu-central-1'

      aws s3 cp --region eu-central-1 ./result s3://cicero-public/test
      aws s3 cp --region eu-central-1 ./result s3://cicero-public/test
    '';

    dependencies = with pkgs; [awscli2];

    nomad = {
      driver = "exec";

      templates = [
        {
          destination = "secrets/aws.env";
          env = true;
          data = ''
            {{with secret "aws/creds/cicero"}}
            AWS_ACCESS_KEY_ID={{.Data.access_key}}
            AWS_SECRET_ACCESS_KEY={{.Data.secret_key}}
            {{end}}
          '';
        }
        {
          destination = "local/default.nix";
          data = ''
            let
              nixpkgs = __getFlake github:NixOS/nixpkgs/6107f97012a0c134c5848125b5aa1b149b76d2c9;
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
            in
              pkgs.runCommand "foo" {} '''
                set -x
                echo '{{timestamp}}' > $out # force a new build
                set +x
              '''
          '';
        }
      ];
    };
  };
}
