# clipway

Host↔guest clipboard for **wlroots** Wayland compositors (Sway, Hyprland, river, …) inside **VMware** guests.

Stock `open-vm-tools` only does X11/GTK clipboard, which can't work on Wayland (and Xwayland is often broken under `vmwgfx`). clipway adds a Wayland backend to the `dndcp` plugin that reuses VMware's copy/paste RPC and drives the local clipboard via `wl-copy`/`wl-paste` (`wlr-data-control`). Works around open-vm-tools [#510](https://github.com/vmware/open-vm-tools/issues/510) / [#792](https://github.com/vmware/open-vm-tools/issues/792).

## Use it (NixOS flake)

```nix
inputs.clipway.url = "github:krisztianfekete/clipway";

# in your system modules:
clipway.nixosModules.default
{
  virtualisation.vmware.guest.enable = true;
  services.clipway.enable = true;        # target defaults to sway-session.target
}
```

The module patches `open-vm-tools` and runs the desktop daemon as a `systemd --user` service. (Overlay only, no service: `clipway.overlays.default`.)

## Other distros

```sh
cd open-vm-tools/                                            # inner source dir
patch -p1 < patches/0001-dndcp-wayland-clipboard-backend.patch
# build as usual, then run inside your Wayland session (needs wl-clipboard on PATH):
XDG_SESSION_TYPE=wayland vmtoolsd -n vmusr
```

## Limits

Text only. `wlr-data-control` compositors only (not GNOME/KDE). Pinned to one open-vm-tools version.

## License

Nix glue: MIT. `patches/`: LGPL-2.1 (inherited from open-vm-tools).
