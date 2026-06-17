self:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.clipway;
in
{
  options.services.clipway = {
    enable = lib.mkEnableOption ''
      clipway: host <-> guest clipboard for wlroots Wayland sessions in VMware
      guests. Applies the open-vm-tools Wayland-clipboard overlay and runs the
      open-vm-tools desktop daemon (vmtoolsd -n vmusr) as a systemd --user
      service bound to your compositor's session target'';

    target = lib.mkOption {
      type = lib.types.str;
      default = "sway-session.target";
      example = "hyprland-session.target";
      description = ''
        The systemd --user target that starts (and stops) the clipboard
        daemon. Use the session target your compositor reaches once
        WAYLAND_DISPLAY has been imported into the user systemd environment.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.open-vm-tools;
      defaultText = lib.literalExpression "pkgs.open-vm-tools";
      description = "The (patched) open-vm-tools package providing vmtoolsd.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Patch open-vm-tools so vmtoolsd ships the Wayland clipboard backend.
    nixpkgs.overlays = [ self.overlays.default ];

    # Stock packaging only launches `vmtoolsd -n vmusr` from X11 session
    # commands, so a Wayland session never gets the desktop (clipboard) daemon.
    # Run it here. The patched backend is selected because XDG_SESSION_TYPE is
    # wayland; wl-clipboard provides the wl-copy/wl-paste it shells out to.
    systemd.user.services.clipway = {
      description = "clipway — open-vm-tools desktop daemon (Wayland clipboard backend)";
      wantedBy = [ cfg.target ];
      after = [ cfg.target ];
      path = [ pkgs.wl-clipboard ];
      serviceConfig = {
        Type = "simple";
        Environment = "XDG_SESSION_TYPE=wayland";
        ExecStart = "${cfg.package}/bin/vmtoolsd -n vmusr";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
