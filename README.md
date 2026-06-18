# clipway

Host - guest clipboard for **wlroots** Wayland compositors (Sway, Hyprland, river, …) inside **VMware** guests.

Stock `open-vm-tools` only ships an X11/GtkClipboard copy-paste backend, which can't work on Wayland (and Xwayland is often broken under `vmwgfx`), so host - guest clipboard is dead in wlroots sessions.

Works around open-vm-tools [#510](https://github.com/vmware/open-vm-tools/issues/510) / [#792](https://github.com/vmware/open-vm-tools/issues/792).

> [!WARNING]
> **Use at your own risk**, it's and unofficial community workaround, not affiliated with or supported by VMware/Broadcom. See [Disclaimer](#disclaimer).

## How it works

clipway adds a Wayland backend to open-vm-tools' `dndcp` plugin that reuses VMware's copy/paste GuestRPC protocol and drives the local clipboard via `wl-copy`/`wl-paste` (`wlr-data-control`, which works for a windowless daemon). It's picked at runtime when `WAYLAND_DISPLAY` is set, so one build serves both X11 and Wayland sessions.

## Requirements

- A VMware guest with copy/paste enabled and the system `vmtoolsd` running (i.e. stock `open-vm-tools` working). Developed against **VMware Fusion** on Apple Silicon; other VMware products untested.
- A **`wlr-data-control`** compositor — Sway, Hyprland, river, … GNOME (Mutter) won't work; KDE/KWin untested.
- **`wl-clipboard`** (`wl-copy`/`wl-paste`) on `PATH`, the backend shells out to it. The NixOS module wires this in.
- The desktop daemon `vmtoolsd -n vmusr` must run **inside** the Wayland session (stock packaging only starts it for X11). The module handles this.
- `open-vm-tools` built **from source** with the patch. Pinned to **13.0.5 / nixpkgs 25.11**; other versions likely need a rebase.

## Nix flake

```nix
inputs.clipway.url = "github:krisztianfekete/clipway";

# in your system modules:
clipway.nixosModules.default
{
  virtualisation.vmware.guest.enable = true;
  services.clipway.enable = true;
  # non-Sway compositors: services.clipway.target = "hyprland-session.target";
}
```

Applies the overlay (patching `open-vm-tools`) and runs the daemon as a `systemd --user` service bound to your compositor's session target. Overlay only, no service: `clipway.overlays.default`.

## Other distros (untested, but should work)

```sh
cd open-vm-tools/
patch -p1 < patches/0001-dndcp-wayland-clipboard-backend.patch
# build as usual, then run inside your Wayland session (needs wl-clipboard on PATH):
XDG_SESSION_TYPE=wayland vmtoolsd -n vmusr
```

## Limitations

- **Plain UTF-8 text only** — no images, RTF/HTML, files, or drag-and-drop. Large selections (over the V3 protocol limit) are dropped.
- **`wlr-data-control` compositors only** (not GNOME; KDE untested).
- Shells out to `wl-clipboard` (no native libwayland client), so it's a hard runtime dependency.
- Pinned to one `open-vm-tools` version; needs rebasing on upgrades and forces a from-source build.
- Verified only on Sway 1.11 / wlroots 0.19.2, VMware Fusion (Professional 25H2 (24995814)), aarch64. Everything else is expected-to-work but unverified.

## Contributing upstream

While I am not the best fit to drive this, the patch is structured to be contributed back to [open-vm-tools](https://github.com/vmware/open-vm-tools) (it would close [#510](https://github.com/vmware/open-vm-tools/issues/510) / [#792](https://github.com/vmware/open-vm-tools/issues/792)). The new files follow the plugin's conventions, and the `fakeMouseWayland/` precedent shows upstream takes Wayland work. The `dndcp` plugin is LGPL-2.1, so the patch's headers already match.

Open questions on the choices made here, which a maintainer may want decided differently:

- **Shell-out vs. native client.** This shells out to `wl-clipboard` instead of embedding a libwayland `wlr-data-control` / `ext-data-control-v1` client. Dependency-free and simple, but upstream would probably prefer no runtime dependency on an external binary.
- **Backend selection.** Picking Wayland when `WAYLAND_DISPLAY` is set (and no `DISPLAY` / `XDG_SESSION_TYPE=wayland`) is a heuristic; upstream may want a build option or explicit capability detection instead.
- **Scope.** Text-only, no DnD, which is fine I guess as a first step, but a roadmap to images/RTF/files would likely be expected.

## Disclaimer

Provided **"as is", without warranty of any kind** (see [`LICENSE`](LICENSE)); **use at your own risk**. This is an unofficial workaround, not affiliated with or endorsed by VMware/Broadcom. It patches and rebuilds a third-party package pinned to a specific version, re-verify after any `open-vm-tools`, nixpkgs, or compositor change. Clipboard contents cross the host/guest boundary by design; don't copy secrets you wouldn't want shared. The authors accept **no liability** for data loss, broken builds, or other damages.

Lower-risk alternative: a network clipboard bridge (e.g. `wl-copy`/`wl-paste` over SSH to the host's `pbcopy`/`pbpaste`) avoids patching `open-vm-tools`.

## License

Nix glue (flake, module): **MIT**. The patch under `patches/` is a derivative of `open-vm-tools`, distributed under **LGPL-2.1** (inherited from upstream).
