{
  description =
    "clipway, a host <-> guest clipboard for wlroots Wayland compositors (Sway, Hyprland, river, …) in VMware guests, via a Wayland backend for open-vm-tools (wlr-data-control / wl-clipboard). Works around open-vm-tools issues #510 and #792.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      patch = ./patches/0001-dndcp-wayland-clipboard-backend.patch;
    in
    {
      # Patch open-vm-tools with the Wayland clipboard backend.
      # Idempotent, so it is safe even if applied alongside the NixOS module.
      overlays.default = final: prev: {
        open-vm-tools = prev.open-vm-tools.overrideAttrs (old: {
          patches = (old.patches or [ ])
            ++ nixpkgs.lib.optional (!builtins.elem patch (old.patches or [ ])) patch;
        });
      };

      # Applies the overlay and runs the desktop daemon as a systemd --user
      # service bound to your compositor's session target.
      nixosModules.default = import ./module.nix self;

      # The patched package, handy for `nix build` and for populating a cache.
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          default = pkgs.open-vm-tools;
          open-vm-tools = pkgs.open-vm-tools;
        });
    };
}
