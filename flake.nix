{
  description =
    "clipway, a host <-> guest clipboard for wlroots Wayland compositors (Sway, Hyprland, river, …) in VMware guests, via a Wayland backend for open-vm-tools (wlr-data-control / wl-clipboard). Works around open-vm-tools issues #510 and #792.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      patch = ./patches/0001-dndcp-wayland-clipboard-backend.patch;
      patchName = baseNameOf (toString patch);

      # The open-vm-tools release the patch is rebased against. If nixpkgs moves
      # off this the patch needs rebasing; checks.<system>.patch-target enforces
      # it, including against floating channels via --override-input.
      patchTargetVersion = "13.0.5";
    in
    {
      # Patch open-vm-tools with the Wayland clipboard backend.
      # Idempotent, so it is safe even if applied alongside the NixOS module.
      overlays.default = final: prev: {
        open-vm-tools = prev.open-vm-tools.overrideAttrs (old: {
          patches = (old.patches or [ ])
            ++ prev.lib.optional (!builtins.elem patch (old.patches or [ ])) patch;
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

      # Evaluation-only checks. They compile nothing, so they are cheap enough to
      # point at a floating nixpkgs channel on a schedule:
      #   nix flake check --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
      checks = forAllSystems (system:
        let
          lib = nixpkgs.lib;
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };

          # A minimal VMware guest, evaluated but never built.
          guest = extra: lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              ({ config, ... }: {
                boot.loader.grub.enable = false;
                fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
                # Track whichever nixpkgs is being evaluated, so overriding the
                # input to another channel does not trip a stateVersion mismatch.
                system.stateVersion = config.system.nixos.release;
                virtualisation.vmware.guest.enable = true;
                services.clipway.enable = true;
              })
              extra
            ];
          };

          # No services.xserver here, so headless follows its nixpkgs default.
          waylandOnly = (guest { }).config;
          withX = (guest { virtualisation.vmware.guest.headless = false; }).config;

          patchesOf = p: map (x: baseNameOf (toString x)) (p.patches or [ ]);
          overlaid = overlays:
            (import nixpkgs { inherit system; inherit overlays; }).open-vm-tools;

          # Forcing toplevel.drvPath proves the whole config evaluates. Its string
          # context carries allOutputs = true, so it MUST be discarded, or
          # `nix flake check` builds the entire NixOS system instead of evaluating it.
          evaluates = cfg:
            builtins.stringLength
              (builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath) > 0;

          report = name: assertions:
            let failed = builtins.filter (a: !a.ok) assertions;
            in
            if failed != [ ] then
              throw "${name}:\n${lib.concatMapStringsSep "\n" (a: "  FAIL ${a.name}") failed}"
            else
              pkgs.writeText name
                (lib.concatMapStringsSep "\n" (a: "ok  ${a.name}") assertions + "\n");
        in
        {
          patch-target = report "clipway-patch-target" [
            {
              name = "nixpkgs open-vm-tools is ${patchTargetVersion}"
                + " (got ${pkgs.open-vm-tools.version};"
                + " if this fails, rebase ${patchName} and bump patchTargetVersion)";
              ok = pkgs.open-vm-tools.version == patchTargetVersion;
            }
          ];

          module-eval = report "clipway-module-eval" [
            {
              name = "minimal wayland guest evaluates end to end";
              ok = evaluates waylandOnly;
            }
            {
              name = "clipway daemon carries ${patchName}";
              ok = builtins.elem patchName (patchesOf waylandOnly.services.clipway.package);
            }
            {
              name = "clipway unit has wl-clipboard on PATH";
              ok = builtins.any (p: (p.pname or "") == "wl-clipboard")
                waylandOnly.systemd.user.services.clipway.path;
            }
            {
              name = "clipway unit is bound to services.clipway.target";
              ok = waylandOnly.systemd.user.services.clipway.wantedBy == [ "sway-session.target" ];
            }
            {
              name = "wayland-only guest still defaults headless to true";
              ok = waylandOnly.virtualisation.vmware.guest.headless;
            }
            {
              name = "wayland-only guest still builds open-vm-tools twice (headless plus patched)";
              ok = waylandOnly.virtualisation.vmware.guest.package.drvPath
                != waylandOnly.services.clipway.package.drvPath;
            }
            {
              name = "headless=false guest shares one open-vm-tools derivation";
              ok = withX.virtualisation.vmware.guest.package.drvPath
                == withX.services.clipway.package.drvPath;
            }
            {
              name = "overlay is idempotent";
              ok = patchesOf (overlaid [ self.overlays.default ])
                == patchesOf (overlaid [ self.overlays.default self.overlays.default ]);
            }
          ];
        });
    };
}
