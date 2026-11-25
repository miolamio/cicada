#!/bin/sh
# Installs Cicada for this user, no sudo: the app in ~/.local/lib/cicada, `cicada` in
# ~/.local/bin, the menu entry and icon in ~/.local/share. Run it again to update; --remove undoes it; --check only checks the libraries
# (records and the Ling key stay in ~/.local/share/cicada and ~/.config/cicada).
set -e
src="$(cd "$(dirname "$0")" && pwd)"
lib="$HOME/.local/lib/cicada"; bin="$HOME/.local/bin"; share="$HOME/.local/share"
if [ "$1" = "--remove" ]; then
  rm -rf "$lib" "$bin/cicada" "$share/applications/com.wquguru.cicada.desktop" "$share/icons/hicolor/scalable/apps/cicada.svg" \
         "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.wquguru.cicada.desktop"
  # The 开始 / 结束听 keyboard shortcut, if it was added in 设置 (it would run a removed program).
  python3 - <<'PY' 2>/dev/null || true
from gi.repository import Gio
schema = "org.gnome.settings-daemon.plugins.media-keys"
if Gio.SettingsSchemaSource.get_default().lookup(schema, True):
    keys = Gio.Settings.new(schema)
    ours = {"/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/%s/" % n for n in ("cicada", "cicada-speak")}
    keys.set_strv("custom-keybindings", [p for p in keys.get_strv("custom-keybindings") if p not in ours])
    Gio.Settings.sync()
PY
  echo "Cicada removed."; exit 0
fi
missing=""
python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null || missing="$missing python3-gi gir1.2-gtk-3.0"
python3 -c 'import ctypes.util, sys; sys.exit(0 if ctypes.util.find_library("pulse-simple") else 1)' || missing="$missing libpulse0"
if [ -n "$missing" ]; then echo "Cicada needs:$missing  (sudo apt install$missing)"; exit 1; fi
# --check: only the checks above (an update runs the new version's before anything is replaced).
[ "$1" = "--check" ] && exit 0
# The new tree is built beside the old one and swapped in, so a copy that fails (disk full) leaves
# the installed version in place instead of nothing.
new="$lib.new"; old="$lib.old"
trap 'rm -rf "$new"' EXIT
rm -rf "$new" "$old"
mkdir -p "$new" "$bin" "$share/applications" "$share/icons/hicolor/scalable/apps"
cp -R "$src/cicada" "$src/lproj" "$src/bin" "$new/"
[ -f "$src/sample.wav" ] && cp "$src/sample.wav" "$new/"
# 说话人识别: the voiceprint weights and libcicada-voice-<arch>.so (speakers.py looks for them here).
for d in models lib; do [ -d "$src/$d" ] && cp -R "$src/$d" "$new/"; done
cp "$src/cicada.svg" "$new/"  # the tray and window icon, by path
cp "$src/VERSION" "$new/"     # read by cicada/__init__.py
if [ -e "$lib" ]; then mv "$lib" "$old"; fi
if ! mv "$new" "$lib"; then
  [ -e "$old" ] && mv "$old" "$lib"
  echo "Cicada could not be installed: the previous version was kept."; exit 1
fi
rm -rf "$old"
ln -sf "$lib/bin/cicada" "$bin/cicada"
bin_esc="$(printf '%s' "$lib/bin/cicada" | sed 's/[\\|&]/\\&/g')"  # a $HOME with | or & must not be sed syntax
sed "s|@BIN@|$bin_esc|" "$src/com.wquguru.cicada.desktop" > "$share/applications/com.wquguru.cicada.desktop"
cp "$src/cicada.svg" "$share/icons/hicolor/scalable/apps/cicada.svg"
gtk-update-icon-cache -q "$share/icons/hicolor" 2>/dev/null || true
echo "Cicada installed: open it from the app grid (知了 / Cicada)."
