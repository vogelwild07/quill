# Layout der .dmg für dmgbuild (Scripts/make-release.sh). Werte per -D:
#   app         Pfad zur geprüften Quill.app
#   background  Scripts/dmg/background.tiff (1× und 2×)
#   icon        AppIcon.icns der App, wird zum Volume-Icon
# Positionen sind die Icon-Mitten in Punkten und müssen zu Scripts/dmg/background.swift
# passen (Pfeil und Namen). Nur Werte aus defines, keine Logik.
import os.path

app = defines["app"]

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Programme": "/Applications"}
# Kein hide_extensions: Es setzt Finder-Informationen am Bundle, codesign --strict
# lehnt die App dann ab. Der Finder blendet „.app“ standardmäßig ohnehin aus.
icon = defines["icon"]
background = defines["background"]

# Fenster 640 × 400 ohne Symbolleiste, Seitenleiste, Pfad- und Statusleiste.
window_rect = ((200, 140), (640, 400))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
grid_spacing = 100
label_pos = "bottom"
text_size = 13
icon_size = 128
icon_locations = {
    os.path.basename(app): (160, 172),
    "Programme": (480, 172),
}
