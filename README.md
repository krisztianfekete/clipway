# clipway

[![nixpkgs-drift](https://github.com/krisztianfekete/clipway/actions/workflows/nixpkgs-drift.yml/badge.svg)](https://github.com/krisztianfekete/clipway/actions/workflows/nixpkgs-drift.yml)

Host - guest clipboard for **wlroots** Wayland compositors (Sway, Hyprland, river, …) inside **VMware** guests.

Stock `open-vm-tools` only ships an X11/GtkClipboard copy-paste backend, which can't work on Wayland (and Xwayland is often broken under `vmwgfx`), so host - guest clipboard is dead in wlroots sessions.

Works around open-vm-tools [#510](https://github.com/vmware/open-vm-tools/issues/510) / [#792](https://github.com/vmware/open-vm-tools/issues/792).

> [!WARNING]
> **Use at your own risk**, it's and unofficial community workaround, not affiliated with or supported by VMware/Broadcom. See [Disclaimer](#disclaimer).

## How it works

clipway adds a Wayland backend to open-vm-tools' `dndcp` plugin that reuses VMware's copy/paste GuestRPC protocol and drives the local clipboard via `wl-copy`/`wl-paste` (`wlr-data-control`, which works for a windowless daemon).
It's picked at runtime when `WAYLAND_DISPLAY` is set, so one build serves both X11 and Wayland sessions.

## Requirements

- A VMware guest with copy/paste enabled and the system `vmtoolsd` running (i.e. stock `open-vm-tools` working). Developed against **VMware Fusion** on Apple Silicon; other VMware products untested.
- A compositor speaking a **data-control** protocol, either `ext-data-control-v1` or the older `wlr-data-control`. Sway, Hyprland, river, … GNOME (Mutter) won't work; KDE/KWin untested. Broadening this from `wlr-data-control` alone is what makes non-wlroots compositors plausible, but nothing outside wlroots has been tried.
- **`wl-clipboard`** (`wl-copy`/`wl-paste`) on `PATH`, the backend shells out to it. The NixOS module wires this in. `wl-clipboard` 2.3.0 speaks both data-control protocols and picks whichever the compositor offers, so clipway doesn't care which one you have.
- The desktop daemon `vmtoolsd -n vmusr` must run **inside** the Wayland session (stock packaging only starts it for X11). The module handles this.
- `open-vm-tools` built **from source** with the patch. The patch targets the **13.0.5** source layout; other `open-vm-tools` versions likely need a rebase. It is *not* tied to a nixpkgs release; see [Verified versions](#verified-versions).

## Verified versions

Re-verified after each upgrade; everything not listed is expected-to-work but untested.

| | Initial (2026-06) | Current (2026-08) |
| --- | --- | --- |
| NixOS / nixpkgs | 25.11 | **26.05** |
| `open-vm-tools` | 13.0.5 | 13.0.5 (unchanged) |
| Sway / wlroots | 1.11 / 0.19.2 | **1.12 / 0.20.0** |
| `wl-clipboard` | 2.3.0 | 2.3.0 (unchanged) |
| Host | VMware Fusion Professional 25H2 (24995814), aarch64 | unchanged |

The NixOS 25.11 → 26.05 upgrade needed **no patch changes**: `open-vm-tools` is still 13.0.5 in 26.05, and wlroots 0.20 still ships `wlr-data-control` alongside the newer `ext-data-control-v1`.

### Re-verifying after an upgrade

```sh
nix eval --raw nixpkgs#open-vm-tools.version   # still 13.0.5? if not, the patch needs a rebase
nix build github:krisztianfekete/clipway       # does the patch still apply and build?
systemctl --user status clipway                # daemon up in the new session?
wl-copy "round trip" && wl-paste               # then paste on the host to check both directions
```

An `open-vm-tools` bump is the change most likely to break clipway: the patch touches `dndcp`'s `Makefile.am` and `copyPasteDnDWrapper.cpp`, so upstream edits to either need a rebase. Compositor upgrades are lower-risk, since clipway only needs *some* data-control protocol and `wl-clipboard` negotiates that.

The first two steps are automated. CI evaluates `nix flake check` daily and builds the patch weekly against `nixos-25.11`, `nixos-26.05` and `nixos-unstable`, so an `open-vm-tools` bump shows up here before it reaches a release channel. You can run the same checks yourself against any channel:

```sh
nix flake check --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
```

`checks.<system>.patch-target` fails when nixpkgs moves off the `open-vm-tools` release the patch targets. `checks.<system>.module-eval` evaluates a minimal VMware guest and pins the module's behaviour, including the headless split described above. Neither compiles anything, so both finish in seconds.

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

**You don't have to match clipway's nixpkgs.** The overlay patches *your* `open-vm-tools` (`prev.open-vm-tools`), so what matters is the `open-vm-tools` version in your nixpkgs, not clipway's. Clipway's own `nixpkgs` input only backs the `packages` output (`nix build`, cache population). It currently tracks `nixos-26.05`; consuming clipway from a 25.11 or unstable system is fine as long as `open-vm-tools` is 13.0.5.

> [!NOTE]
> **Headless guests.** nixpkgs' `virtualisation.vmware.guest.headless` defaults to `!config.services.xserver.enable`, so a pure-Wayland guest gets `headless = true` and the *system* `vmtoolsd` becomes `open-vm-tools-headless`. That build passes `--without-x`, and `dndcp` is gated behind `HAVE_GTKMM` (which requires X), so the headless package contains **no clipboard plugin at all**; the `vmblock` mount and the suid wrapper are skipped too. `services.clipway.package` defaults to `pkgs.open-vm-tools` (patched, X-enabled) regardless, so the clipway daemon itself is unaffected, but this combination is untested. If clipboard doesn't come up on an X-less guest, set `virtualisation.vmware.guest.headless = false`.

## Other distros

```sh
cd open-vm-tools/
patch -p1 < patches/0001-dndcp-wayland-clipboard-backend.patch
# build as usual, then run inside your Wayland session (needs wl-clipboard on PATH):
XDG_SESSION_TYPE=wayland vmtoolsd -n vmusr
```

## Limitations

- **Plain UTF-8 text only** — no images, RTF/HTML, files, or drag-and-drop. Large selections (over the V3 protocol limit) are dropped.
- **Data-control compositors only** (`ext-data-control-v1` or `wlr-data-control`). Not GNOME; KDE untested.
- Shells out to `wl-clipboard` (no native libwayland client), so it's a hard runtime dependency.
- Pinned to one `open-vm-tools` version; needs rebasing on upgrades and forces a from-source build.
- Only the versions in [Verified versions](#verified-versions) are tested. Everything else is expected-to-work but unverified.

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

Nix packaging (flake, module): **MIT**. The patch under `patches/` is a derivative of `open-vm-tools`, distributed under **LGPL-2.1** (inherited from upstream).
