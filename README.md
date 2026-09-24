# clipway

[![nixpkgs-drift](https://github.com/krisztianfekete/clipway/actions/workflows/nixpkgs-drift.yml/badge.svg)](https://github.com/krisztianfekete/clipway/actions/workflows/nixpkgs-drift.yml)

Host/guest clipboard for wlroots Wayland compositors (Sway, Hyprland, river) inside VMware guests.

Stock `open-vm-tools` only has an X11 clipboard backend, so copy and paste between host and guest doesn't work in a wlroots session. This is a workaround for open-vm-tools [#510](https://github.com/vmware/open-vm-tools/issues/510) and [#792](https://github.com/vmware/open-vm-tools/issues/792).

> [!WARNING]
> Unofficial and not affiliated with VMware/Broadcom. Use at your own risk.

## How it works

A patch adds a Wayland backend to the `dndcp` plugin of `open-vm-tools`. It keeps VMware's copy/paste protocol and reads and writes the guest clipboard with `wl-copy`/`wl-paste`, which work for a windowless daemon through the data-control protocols. The backend is chosen at runtime when `WAYLAND_DISPLAY` is set, so one build serves X11 and Wayland sessions.

## Requirements

- A VMware guest with copy/paste enabled. Developed on VMware Fusion (Apple Silicon); other products are untested.
- A compositor with `ext-data-control-v1` or `wlr-data-control`. GNOME won't work; KDE is untested.
- `wl-clipboard` on `PATH`.
- `vmtoolsd -n vmusr` running inside the Wayland session. Stock packaging only starts it for X11; the NixOS module handles this.
- `open-vm-tools` 13.0.5 or 13.1.0 built from source with the patch.

## NixOS

```nix
inputs.clipway.url = "github:krisztianfekete/clipway";

# in your system modules:
clipway.nixosModules.default
{
  virtualisation.vmware.guest.enable = true;
  services.clipway.enable = true;
  # not Sway? services.clipway.target = "hyprland-session.target";
}
```

The module patches your own `open-vm-tools` through an overlay and runs the daemon as a user service bound to the compositor's session target. For the overlay alone, use `clipway.overlays.default`. Your nixpkgs does not have to match clipway's; it only needs to ship one of the supported `open-vm-tools` versions.

Following `main` is normally fine. Each [release](https://github.com/krisztianfekete/clipway/releases) lists the `open-vm-tools` versions it supports, so pin a tag (`github:krisztianfekete/clipway/v0.1.2`) if `main` ever drops the version your channel ships.

> [!NOTE]
> A guest without X defaults to `virtualisation.vmware.guest.headless = true`, and the headless `open-vm-tools` build has no clipboard plugin at all. clipway's own daemon uses the full build either way, but that setup is untested. If the clipboard doesn't come up, set `headless = false`.

## Other distros

```sh
cd open-vm-tools/
patch -p1 < patches/0001-dndcp-wayland-clipboard-backend.patch
# build as usual, then inside your Wayland session:
XDG_SESSION_TYPE=wayland vmtoolsd -n vmusr
```

On Arch there is an AUR package, [open-vm-tools-clipway](https://aur.archlinux.org/packages/open-vm-tools-clipway), maintained by someone else.

## Limitations

- Plain UTF-8 text only. No images, RTF, files or drag and drop, and text over the protocol size limit is dropped. [bazzite-ovt](https://github.com/goproslowyo/bazzite-ovt) builds on this backend and covers those.
- Hard runtime dependency on `wl-clipboard`.
- The patch targets specific `open-vm-tools` releases and needs a rebase when upstream changes `dndcp`.

## Verified on

NixOS 26.05, `open-vm-tools` 13.0.5 and 13.1.0, Sway 1.12 / wlroots 0.20, `wl-clipboard` 2.3.0, VMware Fusion Professional 25H2 on aarch64.

CI evaluates the flake daily and builds the patch weekly against `nixos-25.11`, `nixos-26.05` and `nixos-unstable`, so an `open-vm-tools` bump shows up here before it reaches a release channel. The build also checks that the Wayland backend actually made it into `libdndcp.so`, since a patch can apply with fuzz and still miss.

If you edit the patch: the `Makefile.am` hunk anchors on the `if LINUX` block and adds the sources at the top level on purpose. 13.1.0 moved the X11 sources into `HAVE_GTK4` branches, and anchoring there would drop the backend on some builds.

## Upstreaming

The patch follows the plugin's conventions and is licensed to match, so it could go upstream. Things a maintainer would likely want changed: a native data-control client instead of shelling out to `wl-clipboard`, explicit backend selection instead of an environment heuristic, and support beyond plain text.

## License

The Nix packaging is MIT. The patch is derived from `open-vm-tools` and is LGPL-2.1. Provided as is, without warranty; see [`LICENSE`](LICENSE). Clipboard contents cross the host/guest boundary by design, so don't copy anything you wouldn't want shared.
