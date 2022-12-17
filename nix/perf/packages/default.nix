{
  inputs,
  cell,
}: {
  postgrest = inputs.nixpkgs-postgrest.legacyPackages.x86_64-linux.haskellPackages.postgrest;
}
