#!/usr/bin/env bash
#
# setup-workspace-shortcuts.sh
#
# Ρυθμίζει το Super+1..6 ώστε να εναλλάσσει fixed workspaces στο GNOME
# (Ubuntu), αντί να ανοίγει εφαρμογές από το Dock. Κάνει επίσης swap
# Caps Lock <-> Ctrl (HHKB-style layout).
#
# Τι κάνει:
#   1. Ορίζει 6 σταθερά (μη-δυναμικά) workspaces.
#   2. Απενεργοποιεί τα κρυφά "switch to application 1-9" shortcuts
#      του GNOME Shell (δεν εμφανίζονται στο Settings GUI).
#   3. Απενεργοποιεί τα hotkeys του Dash to Dock extension
#      (Super+1..0, Ctrl+Super+1..0, Shift+Super+1..0), αν υπάρχει.
#   4. Ορίζει Super+1..6 -> εναλλαγή σε workspace 1..6.
#   5. (Προαιρετικά) Super+Shift+1..6 -> μεταφορά τρέχοντος παραθύρου
#      στο workspace 1..6.
#   6. Κάνει swap Caps Lock <-> Ctrl (HHKB-style).
#
# Χρήση:
#   chmod +x setup-workspace-shortcuts.sh
#   ./setup-workspace-shortcuts.sh
#
# Χρειάζεται να τρέξει μέσα σε γραφικό session (GNOME), όχι π.χ. TTY/SSH
# χωρίς DISPLAY, γιατί το gsettings γράφει στο dconf του τρέχοντος χρήστη.

set -e

NUM_WORKSPACES=6

echo "==> Ορισμός $NUM_WORKSPACES σταθερών workspaces..."
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces "$NUM_WORKSPACES"

echo "==> Απενεργοποίηση κρυφών 'switch to application' shortcuts (Super+1..9)..."
for i in $(seq 1 9); do
  gsettings set org.gnome.shell.keybindings switch-to-application-$i "[]"
done

if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-dock"; then
  echo "==> Βρέθηκε Dash to Dock: απενεργοποίηση των δικών του hotkeys..."
  gsettings set org.gnome.shell.extensions.dash-to-dock hot-keys false
else
  echo "==> Δεν βρέθηκε Dash to Dock, παράλειψη αυτού του βήματος."
fi

echo "==> Ορισμός Super+1..$NUM_WORKSPACES για εναλλαγή workspace..."
for i in $(seq 1 $NUM_WORKSPACES); do
  gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-$i "['<Super>$i']"
done

echo "==> Ορισμός Super+Shift+1..$NUM_WORKSPACES για μεταφορά παραθύρου σε workspace..."
for i in $(seq 1 $NUM_WORKSPACES); do
  gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-$i "['<Super><Shift>$i']"
done

echo "==> Swap Caps Lock <-> Ctrl (HHKB-style)..."
# Προσοχή: αυτό αντικαθιστά ΟΛΗ τη λίστα xkb-options. Αν χρησιμοποιείς
# κι άλλα xkb-options (π.χ. για άλλη γλώσσα πληκτρολογίου), πρόσθεσέ τα
# εδώ μέσα στη λίστα αντί να τα αφήσεις να σβηστούν.
gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:swapcaps']"

echo ""
echo "Έτοιμο! Το Super+1..$NUM_WORKSPACES πρέπει τώρα να εναλλάσσει workspaces,"
echo "και το Caps Lock / Ctrl είναι swapped (HHKB-style)."
echo "Αν κάτι δεν δουλέψει, μπορεί να χρειαστεί logout/login ή restart του GNOME Shell."
