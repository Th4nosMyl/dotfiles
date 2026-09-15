#!/usr/bin/env bash
#
# setup-alacritty-default.sh
# Κάνει το Alacritty τον default terminal emulator σε Ubuntu / GNOME.
# Είναι idempotent: μπορείς να το τρέξεις όσες φορές θέλεις.
#
# Χρήση:
#   ./setup-alacritty-default.sh            # κανονικό τρέξιμο
#   ./setup-alacritty-default.sh --dry-run  # δείχνει τι θα έκανε, χωρίς αλλαγές
#   ./setup-alacritty-default.sh --nautilus # και "Open in Terminal" στο Nautilus
#

set -euo pipefail

DRY_RUN=0
DO_NAUTILUS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=1 ;;
    --nautilus) DO_NAUTILUS=1 ;;
    -h|--help)
      sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Άγνωστο option: $arg" >&2; exit 1 ;;
  esac
done

# ---------- helpers ----------

C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'
C_INFO=$'\033[0;34m'; C_OFF=$'\033[0m'

ok()   { echo "${C_OK}  ✓${C_OFF} $*"; }
warn() { echo "${C_WARN}  !${C_OFF} $*"; }
err()  { echo "${C_ERR}  ✗${C_OFF} $*" >&2; }
step() { echo; echo "${C_INFO}==>${C_OFF} $*"; }

run() {
  if (( DRY_RUN )); then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Υπάρχει ζωντανό GNOME/dbus session; (αλλιώς τα gsettings δεν έχουν νόημα)
gnome_session() {
  have gsettings && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]
}

# ---------- 0. Έλεγχος ότι υπάρχει το Alacritty ----------

step "Έλεγχος εγκατάστασης"

if ! have alacritty; then
  err "Δεν βρέθηκε το alacritty στο PATH."
  echo "    Εγκατάστησέ το πρώτα, π.χ.:  sudo apt install alacritty"
  exit 1
fi

ALACRITTY_BIN="$(command -v alacritty)"
ok "Βρέθηκε: $ALACRITTY_BIN"

# ---------- 1. update-alternatives (x-terminal-emulator) ----------

step "Ρύθμιση x-terminal-emulator"

if have update-alternatives; then
  if ! update-alternatives --list x-terminal-emulator 2>/dev/null | grep -qxF "$ALACRITTY_BIN"; then
    run sudo update-alternatives --install /usr/bin/x-terminal-emulator \
        x-terminal-emulator "$ALACRITTY_BIN" 60
    ok "Καταχωρήθηκε ως alternative"
  else
    ok "Ήδη καταχωρημένο ως alternative"
  fi

  run sudo update-alternatives --set x-terminal-emulator "$ALACRITTY_BIN"
  ok "Ορίστηκε ως το ενεργό x-terminal-emulator"
else
  warn "Δεν υπάρχει update-alternatives — παραλείπεται"
fi

# ---------- 2. GNOME default-applications ----------

step "GNOME default terminal"

if gnome_session; then
  run gsettings set org.gnome.desktop.default-applications.terminal exec "$ALACRITTY_BIN"
  run gsettings set org.gnome.desktop.default-applications.terminal exec-arg "-e"
  ok "org.gnome.desktop.default-applications.terminal → alacritty"
else
  warn "Δεν εντοπίστηκε ενεργό GNOME session — παραλείπεται"
fi

# ---------- 3. XDG xdg-terminals.list ----------

step "XDG terminal list"

DESKTOP_FILE=""
for d in "$HOME/.local/share/applications" /usr/share/applications; do
  [[ -d "$d" ]] || continue
  found="$(find "$d" -maxdepth 1 -iname '*alacritty*.desktop' -printf '%f\n' 2>/dev/null | head -n1 || true)"
  if [[ -n "$found" ]]; then
    DESKTOP_FILE="$found"
    break
  fi
done

if [[ -n "$DESKTOP_FILE" ]]; then
  XDG_LIST="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list"
  if [[ -f "$XDG_LIST" ]] && grep -qxF "$DESKTOP_FILE" "$XDG_LIST"; then
    ok "Ήδη στο $XDG_LIST"
  else
    run mkdir -p "$(dirname "$XDG_LIST")"
    if (( DRY_RUN )); then
      echo "    [dry-run] echo '$DESKTOP_FILE' > $XDG_LIST"
    else
      printf '%s\n' "$DESKTOP_FILE" > "$XDG_LIST"
    fi
    ok "Γράφτηκε το $DESKTOP_FILE στο $XDG_LIST"
  fi
else
  warn "Δεν βρέθηκε .desktop αρχείο για το Alacritty — παραλείπεται"
fi

# ---------- 4. Ctrl+Alt+T ----------

step "Συντόμευση Ctrl+Alt+T"

if gnome_session; then
  MK="org.gnome.settings-daemon.plugins.media-keys"
  BPATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/alacritty/"

  # Καθάρισμα του built-in binding, αλλιώς συγκρούεται
  run gsettings set "$MK" terminal "[]"

  current="$(gsettings get "$MK" custom-keybindings 2>/dev/null || echo "@as []")"
  if [[ "$current" != *"$BPATH"* ]]; then
    if [[ "$current" == "@as []" || "$current" == "[]" ]]; then
      newlist="['$BPATH']"
    else
      newlist="${current%]}, '$BPATH']"
    fi
    run gsettings set "$MK" custom-keybindings "$newlist"
  fi

  run gsettings set "${MK}.custom-keybinding:${BPATH}" name    "Alacritty"
  run gsettings set "${MK}.custom-keybinding:${BPATH}" command "$ALACRITTY_BIN"
  run gsettings set "${MK}.custom-keybinding:${BPATH}" binding "<Control><Alt>t"
  ok "Ctrl+Alt+T → alacritty"
else
  warn "Δεν εντοπίστηκε ενεργό GNOME session — παραλείπεται"
fi

# ---------- 5. $TERMINAL ----------

step "Μεταβλητή TERMINAL"

PROFILE="$HOME/.profile"
LINE='export TERMINAL=alacritty'

if [[ -f "$PROFILE" ]] && grep -qxF "$LINE" "$PROFILE"; then
  ok "Ήδη υπάρχει στο $PROFILE"
else
  if (( DRY_RUN )); then
    echo "    [dry-run] append '$LINE' >> $PROFILE"
  else
    printf '\n# set by setup-alacritty-default.sh\n%s\n' "$LINE" >> "$PROFILE"
  fi
  ok "Προστέθηκε στο $PROFILE (ισχύει μετά από logout/login)"
fi

# ---------- 6. Nautilus (προαιρετικό) ----------

if (( DO_NAUTILUS )); then
  step "Nautilus \"Open in Terminal\""

  if ! dpkg -s nautilus-open-any-terminal >/dev/null 2>&1; then
    run sudo apt-get install -y nautilus-open-any-terminal
  fi

  if gnome_session; then
    run gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal alacritty
    ok "Ρυθμίστηκε σε alacritty (θέλει: nautilus -q)"
  fi
fi

# ---------- Verification ----------

step "Έλεγχος"

if have update-alternatives; then
  actual="$(readlink -f /usr/bin/x-terminal-emulator 2>/dev/null || echo '-')"
  if [[ "$actual" == "$(readlink -f "$ALACRITTY_BIN")" ]]; then
    ok "x-terminal-emulator → $actual"
  else
    warn "x-terminal-emulator → $actual (αναμενόταν $ALACRITTY_BIN)"
  fi
fi

if gnome_session; then
  ok "GNOME exec: $(gsettings get org.gnome.desktop.default-applications.terminal exec)"
fi

echo
if (( DRY_RUN )); then
  echo "${C_WARN}Dry run — δεν έγινε καμία αλλαγή.${C_OFF}"
else
  echo "${C_OK}Έτοιμο.${C_OFF} Κάνε logout/login για να ισχύσουν όλα."
fi
