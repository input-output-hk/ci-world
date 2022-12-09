{lib, ...}: {
  nix = {
    # To avoid build problems in containers
    sandboxPaths = ["/etc/nsswitch.conf" "/etc/protocols"];

    # To avoid interactive prompts on flake nix config declarations
    extraOptions = lib.mkForce ''
      accept-flake-config = true
    '';
  };
}
