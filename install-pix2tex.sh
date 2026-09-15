#!/usr/bin/env bash
#
# install-pix2tex.sh — pix2tex / LaTeX-OCR setup for Ubuntu
#
# Screenshot -> LaTeX. Sets up an isolated venv, CPU-only PyTorch,
# the GUI extras and the screenshot backend for your session type.
#
# Usage:
#   ./install-pix2tex.sh              install (or repair) the environment
#   ./install-pix2tex.sh --clean      wipe the venv first, then install
#   ./install-pix2tex.sh --check      verify an existing install, change nothing
#   ./install-pix2tex.sh --uninstall  remove the venv, caches and alias
#   ./install-pix2tex.sh --no-apt     skip apt steps (no sudo needed)
#   ./install-pix2tex.sh --venv PATH  use a different venv location
#
# Nothing is installed into the system Python. Everything lives in the venv.

set -euo pipefail

# ---------------------------------------------------------------- settings --

VENV="${PIX2TEX_VENV:-$HOME/venvs/pix2tex}"
# pix2tex has had no release since early 2025; its pinned deps get unhappy on
# very new interpreters. These are the versions known to behave, best first.
PREFERRED_PYTHONS=(python3.11 python3.12 python3.10)
FALLBACK_PYTHON_PKG="python3.11"

DO_APT=1
DO_CLEAN=0
CHECK_ONLY=0
UNINSTALL=0

# ----------------------------------------------------------------- helpers --

if [[ -t 1 ]]; then
    B=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; R=$'\033[0m'
else
    B=""; GREEN=""; YELLOW=""; RED=""; R=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$GREEN" "$R" "$B" "$*" "$R"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$R" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

apt_install() {
    local missing=()
    for pkg in "$@"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        info "already present: $*"
        return 0
    fi
    info "installing: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}"
}

# -------------------------------------------------------------------- args --

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)     DO_CLEAN=1 ;;
        --check)     CHECK_ONLY=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --no-apt)    DO_APT=0 ;;
        --venv)      VENV="${2:?--venv needs a path}"; shift ;;
        -h|--help)   sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] && die "don't run this as root — it installs into \$HOME"

# --------------------------------------------------------------- uninstall --

if [[ $UNINSTALL -eq 1 ]]; then
    step "Removing pix2tex"
    rm -rf "$VENV"
    rm -rf "$HOME/.cache/huggingface/hub/models--"*pix2tex* 2>/dev/null || true
    if [[ -f "$HOME/.bashrc" ]]; then
        sed -i '/# pix2tex (managed by install-pix2tex.sh)/,+1d' "$HOME/.bashrc"
    fi
    info "venv, model cache and alias removed"
    info "apt packages were left alone — they're generally useful"
    exit 0
fi

# ------------------------------------------------------------------- check --

verify() {
    local py="$VENV/bin/python"
    [[ -x "$py" ]] || { warn "no venv at $VENV"; return 1; }

    step "Verifying"
    info "python: $("$py" --version 2>&1)"

    "$py" - <<'PY' || return 1
import sys

def check(label, fn):
    try:
        fn()
    except Exception as e:
        print(f"    [x] {label}: {type(e).__name__}: {e}")
        sys.exit(1)
    print(f"    [ok] {label}")

check("torch",   lambda: __import__("torch"))
check("PyQt6",   lambda: __import__("PyQt6.QtWidgets", fromlist=["QtWidgets"]))
check("pix2tex", lambda: __import__("pix2tex.cli", fromlist=["cli"]))

# The classic breakage: latex2sympy2 pins antlr4 4.7.2, which explodes on
# Python >= 3.10 with "typing.io is not a package".
import antlr4
from importlib.metadata import version
v = version("antlr4-python3-runtime")
if tuple(int(x) for x in v.split(".")[:2]) < (4, 9):
    print(f"    [x] antlr4-python3-runtime {v} is too old — run this script again to repair")
    sys.exit(1)
print(f"    [ok] antlr4-python3-runtime {v}")
PY

    # Smoke test: load the weights and push one image through. Proves the
    # pipeline runs end to end — it is not an accuracy test.
    info "loading model (first run downloads checkpoints, be patient)..."
    "$py" - <<'PY' || return 1
import warnings; warnings.filterwarnings("ignore")
from PIL import Image, ImageDraw
from pix2tex.cli import LatexOCR

img = Image.new("L", (240, 60), 255)
ImageDraw.Draw(img).text((12, 20), "E = mc^2", fill=0)

out = LatexOCR()(img)
print(f"    [ok] inference ran, model returned: {out!r}")
PY

    printf '\n%s[ok]%s pix2tex is working. Launch it with: %slatexocr%s\n' \
        "$GREEN" "$R" "$B" "$R"
}

if [[ $CHECK_ONLY -eq 1 ]]; then
    verify || die "verification failed — rerun without --check to repair"
    exit 0
fi

# ------------------------------------------------------------ apt packages --

if [[ $DO_APT -eq 1 ]]; then
    have apt-get || die "this script targets Debian/Ubuntu (no apt-get found)"

    step "System packages"
    sudo apt-get update -qq

    # build-essential + python3-dev: evdev (via pynput) has no wheels and is
    # compiled from source, so it needs Python.h and linux/input.h.
    # libxcb-cursor0 + libgl1 + libegl1: Qt's xcb platform plugin.
    apt_install build-essential linux-libc-dev libxcb-cursor0 libgl1 libegl1

    step "Screenshot backend"
    case "${XDG_SESSION_TYPE:-}" in
        wayland)
            info "Wayland session detected"
            apt_install grim slurp
            ;;
        x11)
            info "X11 session detected"
            apt_install gnome-screenshot
            ;;
        *)
            warn "could not detect session type — installing both backends"
            apt_install gnome-screenshot grim slurp
            ;;
    esac
fi

# ------------------------------------------------------------ interpreter --

step "Python interpreter"

PY_BIN=""
for candidate in "${PREFERRED_PYTHONS[@]}"; do
    if have "$candidate"; then
        PY_BIN="$candidate"
        break
    fi
done

if [[ -z "$PY_BIN" ]]; then
    [[ $DO_APT -eq 1 ]] || die "none of ${PREFERRED_PYTHONS[*]} found and --no-apt was given"
    warn "no suitable interpreter found — installing $FALLBACK_PYTHON_PKG"
    if ! apt-cache show "$FALLBACK_PYTHON_PKG" >/dev/null 2>&1; then
        info "adding deadsnakes PPA"
        apt_install software-properties-common
        sudo add-apt-repository -y ppa:deadsnakes/ppa
        sudo apt-get update -qq
    fi
    apt_install "$FALLBACK_PYTHON_PKG" "${FALLBACK_PYTHON_PKG}-venv" "${FALLBACK_PYTHON_PKG}-dev"
    PY_BIN="$FALLBACK_PYTHON_PKG"
fi

info "using $PY_BIN ($("$PY_BIN" --version 2>&1))"

if [[ $DO_APT -eq 1 ]]; then
    # Headers must match the exact interpreter building evdev, not whatever
    # python3-dev happens to point at.
    PY_MM="$("$PY_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
    apt_install "python${PY_MM}-dev" "python${PY_MM}-venv" || \
        warn "python${PY_MM}-dev unavailable — the evdev build may fail"
fi

# ------------------------------------------------------------------- venv --

if [[ $DO_CLEAN -eq 1 && -d "$VENV" ]]; then
    step "Wiping existing venv"
    rm -rf "$VENV"
fi

step "Virtual environment"
if [[ -x "$VENV/bin/python" ]]; then
    info "reusing $VENV"
else
    info "creating $VENV"
    mkdir -p "$(dirname "$VENV")"
    "$PY_BIN" -m venv "$VENV"
fi

PIP="$VENV/bin/pip"
"$PIP" install --quiet --upgrade pip wheel setuptools

# --------------------------------------------------------------- packages --

step "PyTorch (CPU build)"
# Installed separately and on purpose: the default wheels drag in ~3 GB of
# CUDA libraries that are useless for one-formula-at-a-time inference.
if "$VENV/bin/python" -c 'import torch' 2>/dev/null; then
    info "already installed"
else
    "$PIP" install torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi

step "pix2tex + GUI extras"
"$PIP" install "pix2tex[gui]"

step "Dependency fixups"
# latex2sympy2 pins antlr4-python3-runtime==4.7.2, which is broken on modern
# Python. 4.9.2 works fine despite the metadata — pip will print a conflict
# warning here and that warning is expected and safe to ignore.
"$PIP" install --quiet "antlr4-python3-runtime==4.9.2"
info "antlr4 pinned to 4.9.2 (pip's conflict warning about 4.7.2 is expected)"

# ------------------------------------------------------------------ alias --

if [[ -f "$HOME/.bashrc" ]] && ! grep -q "# pix2tex (managed by install-pix2tex.sh)" "$HOME/.bashrc"; then
    step "Shell alias"
    {
        echo "# pix2tex (managed by install-pix2tex.sh)"
        echo "alias latexocr='$VENV/bin/latexocr'"
    } >> "$HOME/.bashrc"
    info "added 'latexocr' alias to ~/.bashrc (new shells only)"
fi

# ----------------------------------------------------------------- verify --

verify || die "install finished but verification failed"

cat <<EOF

    binary:  $VENV/bin/latexocr
    hotkey:  Settings -> Keyboard -> Custom Shortcuts -> $VENV/bin/latexocr
EOF

if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    cat <<'EOF'
    wayland: gnome-screenshot wins when installed but breaks on wlroots
             compositors (Sway, Hyprland). If snipping misbehaves, run:
             SCREENSHOT_TOOL=grim latexocr
EOF
fi

echo
