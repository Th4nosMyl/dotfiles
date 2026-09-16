#!/bin/bash
# Sets up LaTeX-OCR (pix2tex) GUI on Ubuntu/GNOME (Wayland).
#
# Usage: ./setup_latexocr.sh
#
# Workflow after setup (GNOME's screenshot D-Bus call is blocked on
# newer GNOME Shell, so pix2tex's own Snip/Alt+S button does NOT work
# — don't use it):
#   1. Open "LaTeX-OCR" from the app launcher.
#   2. Press PrtScn, select "Selection", drag over the equation, copy
#      it to the clipboard from the on-screen toolbar.
#   3. Click the LaTeX-OCR window and press Ctrl+V.

set -euo pipefail

INSTALL_DIR="$HOME/latexocr"
VENV_DIR="$INSTALL_DIR/venv"
DESKTOP_FILE="$HOME/.local/share/applications/latexocr.desktop"

echo "==> Installing system dependencies (python3.11, venv)"
sudo apt update
sudo apt install -y python3.11 python3.11-venv

mkdir -p "$INSTALL_DIR"

if [ ! -d "$VENV_DIR" ]; then
    echo "==> Creating virtualenv at $VENV_DIR"
    python3.11 -m venv "$VENV_DIR"
else
    echo "==> Virtualenv already exists at $VENV_DIR, reusing it"
fi

echo "==> Installing pix2tex[gui] into the virtualenv"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install "pix2tex[gui]"

echo "==> Writing launcher script"
cat > "$INSTALL_DIR/run_latexocr.sh" <<EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
exec pix2tex_gui
EOF
chmod +x "$INSTALL_DIR/run_latexocr.sh"

echo "==> Writing desktop launcher entry"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=LaTeX-OCR
Comment=Screenshot equations and convert them to LaTeX
Exec=$INSTALL_DIR/run_latexocr.sh
Icon=accessories-calculator
Terminal=false
Categories=Education;Science;Utility;
EOF
chmod +x "$DESKTOP_FILE"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo "==> Done. Launch 'LaTeX-OCR' from your app menu, or run: $INSTALL_DIR/run_latexocr.sh"
echo "    (first launch downloads the model weights, ~115MB)"
