#!/usr/bin/env bash
#
# install-pix2tex.sh — pix2tex / LaTeX-OCR for Ubuntu (GNOME Wayland)
#
# Clipboard image -> LaTeX in your clipboard, via a hotkey.
#
# The upstream GUI's "Snip" button cannot work on GNOME Wayland: it needs
# either wlr-screencopy (grim — Mutter doesn't implement it), X11 screen
# access (PIL), or an unsandboxed gnome-screenshot, and Mutter blocks all
# three. So this sets up a different flow that does work:
#
#     Shift+PrtScr  -> GNOME's own area capture, lands in the clipboard
#     Super+L       -> pix2tex-snip reads it, OCRs it, replaces the
#                      clipboard with the LaTeX, shows a notification
#
# A small daemon keeps the model in memory, so each snip takes ~1s instead
# of reloading ~10s of weights. It runs as a systemd user service.
#
# Usage:
#   ./install-pix2tex.sh              install or repair
#   ./install-pix2tex.sh --clean      wipe the venv first, then install
#   ./install-pix2tex.sh --check      verify only, change nothing
#   ./install-pix2tex.sh --uninstall  remove everything this script added
#   ./install-pix2tex.sh --with-gui   also install the Qt GUI (X11 only)
#   ./install-pix2tex.sh --no-apt     skip apt steps (no sudo needed)
#   ./install-pix2tex.sh --venv PATH  use a different venv location
#
# Nothing is installed into the system Python.

set -euo pipefail

# ---------------------------------------------------------------- settings --

VENV="${PIX2TEX_VENV:-$HOME/venvs/pix2tex}"
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_NAME="pix2tex.service"
SNIP="$BIN_DIR/pix2tex-snip"

# pix2tex has had no release since early 2025 and its pinned deps break on
# very new interpreters. Best-behaved first.
PREFERRED_PYTHONS=(python3.11 python3.12 python3.10)
FALLBACK_PYTHON_PKG="python3.11"

DO_APT=1
DO_CLEAN=0
CHECK_ONLY=0
UNINSTALL=0
WITH_GUI=0

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
        --with-gui)  WITH_GUI=1 ;;
        --no-apt)    DO_APT=0 ;;
        --venv)      VENV="${2:?--venv needs a path}"; shift ;;
        -h|--help)   sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] && die "don't run this as root — it installs into \$HOME"

# --------------------------------------------------------------- uninstall --

if [[ $UNINSTALL -eq 1 ]]; then
    step "Removing pix2tex"
    systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
    rm -f "$UNIT_DIR/$UNIT_NAME"
    systemctl --user daemon-reload 2>/dev/null || true
    rm -f "$SNIP"
    rm -rf "$VENV"
    rm -rf "$HOME/.cache/huggingface/hub/"*pix2tex* 2>/dev/null || true
    if [[ -f "$HOME/.bashrc" ]]; then
        sed -i '/# pix2tex (managed by install-pix2tex.sh)/,+1d' "$HOME/.bashrc"
    fi
    info "venv, daemon, service and model cache removed"
    info "apt packages were left alone — they're generally useful"
    info "remove the keyboard shortcut by hand in Settings"
    exit 0
fi

# ------------------------------------------------------------------ verify --

verify() {
    local py="$VENV/bin/python"
    [[ -x "$py" ]] || { warn "no venv at $VENV"; return 1; }

    step "Verifying"
    info "python: $("$py" --version 2>&1)"

    "$py" - <<'PY' || return 1
import sys
from importlib.metadata import version

def check(label, fn):
    try:
        fn()
    except Exception as e:
        print(f"    [x] {label}: {type(e).__name__}: {e}")
        sys.exit(1)
    print(f"    [ok] {label}")

check("torch",   lambda: __import__("torch"))
check("pix2tex", lambda: __import__("pix2tex.cli", fromlist=["cli"]))

# latex2sympy2 pins antlr4 4.7.2, which explodes on Python >= 3.10 with
# "typing.io is not a package". 4.9.2 works despite the metadata warning.
v = version("antlr4-python3-runtime")
if tuple(int(x) for x in v.split(".")[:2]) < (4, 9):
    print(f"    [x] antlr4-python3-runtime {v} too old — rerun to repair")
    sys.exit(1)
print(f"    [ok] antlr4-python3-runtime {v}")
PY

    local tool
    for tool in wl-paste wl-copy notify-send; do
        if have "$tool"; then
            info "[ok] $tool"
        else
            warn "[x] $tool missing"
            return 1
        fi
    done

    [[ -x "$SNIP" ]] || { warn "pix2tex-snip not installed"; return 1; }
    info "[ok] $SNIP"

    if systemctl --user is-active --quiet "$UNIT_NAME"; then
        info "[ok] daemon running"
    else
        warn "daemon not running — start with: systemctl --user start $UNIT_NAME"
    fi

    # End-to-end: render a formula image, push it through the real pipeline.
    info "running end-to-end test (first run downloads weights, be patient)..."
    "$SNIP" --self-test || return 1

    printf '\n%s[ok]%s pix2tex is working.\n' "$GREEN" "$R"
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
    apt_install wl-clipboard libnotify-bin

    if [[ $WITH_GUI -eq 1 ]]; then
        # Only the Qt GUI needs these: evdev (via pynput) compiles from source.
        apt_install build-essential linux-libc-dev libxcb-cursor0 libgl1 libegl1
    fi
fi

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
    warn "session type is '${XDG_SESSION_TYPE:-unknown}', not wayland"
    warn "the clipboard flow uses wl-paste and needs a Wayland session"
fi

# ------------------------------------------------------------- interpreter --

step "Python interpreter"

PY_BIN=""
for candidate in "${PREFERRED_PYTHONS[@]}"; do
    have "$candidate" && { PY_BIN="$candidate"; break; }
done

if [[ -z "$PY_BIN" ]]; then
    [[ $DO_APT -eq 1 ]] || die "none of ${PREFERRED_PYTHONS[*]} found and --no-apt given"
    warn "no suitable interpreter — installing $FALLBACK_PYTHON_PKG"
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

if [[ $DO_APT -eq 1 && $WITH_GUI -eq 1 ]]; then
    # Headers must match the exact interpreter that builds evdev.
    PY_MM="$("$PY_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
    apt_install "python${PY_MM}-dev" || warn "python${PY_MM}-dev unavailable"
fi

# -------------------------------------------------------------------- venv --

if [[ $DO_CLEAN -eq 1 && -d "$VENV" ]]; then
    step "Wiping existing venv"
    systemctl --user stop "$UNIT_NAME" 2>/dev/null || true
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

step "PyTorch (CPU build)"
# Separate on purpose: the default wheels pull ~3 GB of CUDA libraries that
# are useless for one-formula-at-a-time inference.
if "$VENV/bin/python" -c 'import torch' 2>/dev/null; then
    info "already installed"
else
    "$PIP" install torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi

step "pix2tex"
if [[ $WITH_GUI -eq 1 ]]; then
    "$PIP" install "pix2tex[gui]"
else
    # No [gui] extra: skips PyQt6 and pynput/evdev entirely. evdev has no
    # wheels and is the usual source of build failures, and the GUI can't
    # snip on GNOME Wayland anyway.
    "$PIP" install pix2tex
fi

step "Dependency fixups"
"$PIP" install --quiet "antlr4-python3-runtime==4.9.2"
info "antlr4 pinned to 4.9.2 (pip's conflict warning about 4.7.2 is expected)"

# --------------------------------------------------------------- snip tool --

step "Installing pix2tex-snip"
mkdir -p "$BIN_DIR"

printf '#!%s\n' "$VENV/bin/python" > "$SNIP"

cat >> "$SNIP" <<'PYEOF'
"""
pix2tex-snip — clipboard image to LaTeX.

Modes:
  pix2tex-snip              OCR the clipboard image, put LaTeX in clipboard
  pix2tex-snip --daemon     run the model server (systemd uses this)
  pix2tex-snip --self-test  render a formula, push it through, report
  pix2tex-snip --purge      also delete the screenshot GNOME just saved
"""
import io
import os
import sys
import socket
import struct
import signal
import time
import subprocess

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
SOCK_PATH = os.path.join(RUNTIME, "pix2tex.sock")
SHOTS_DIR = os.path.join(os.path.expanduser("~"), "Pictures", "Screenshots")


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --- length-prefixed framing over the socket -------------------------------

def send_msg(conn, payload):
    conn.sendall(struct.pack("!Q", len(payload)) + payload)


def recv_exactly(conn, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(min(65536, n - len(buf)))
        if not chunk:
            raise ConnectionError("connection closed early")
        buf.extend(chunk)
    return bytes(buf)


def recv_msg(conn):
    (n,) = struct.unpack("!Q", recv_exactly(conn, 8))
    return recv_exactly(conn, n)


def load_model():
    import warnings
    warnings.filterwarnings("ignore")
    from PIL import Image
    from pix2tex.cli import LatexOCR
    model = LatexOCR()
    return lambda data: model(Image.open(io.BytesIO(data)))


# --- daemon ----------------------------------------------------------------

def run_daemon():
    predict = load_model()

    if os.path.exists(SOCK_PATH):
        os.unlink(SOCK_PATH)

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK_PATH)
    os.chmod(SOCK_PATH, 0o600)
    srv.listen(4)
    log("ready on", SOCK_PATH)

    def cleanup(*_):
        try:
            os.unlink(SOCK_PATH)
        except OSError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    while True:
        conn, _ = srv.accept()
        with conn:
            try:
                data = recv_msg(conn)
                try:
                    reply = "OK\t" + predict(data)
                except Exception as e:
                    reply = "ERR\t%s: %s" % (type(e).__name__, e)
                send_msg(conn, reply.encode("utf-8"))
                log(reply[:70])
            except Exception as e:
                log("connection error:", e)


# --- client ----------------------------------------------------------------

def clipboard_image():
    for mime in ("image/png", "image/jpeg"):
        try:
            out = subprocess.run(["wl-paste", "--type", mime],
                                 capture_output=True, check=True).stdout
            if out:
                return out
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return b""


def notify(title, body=""):
    # Never let a missing notifier take down the whole snip.
    try:
        subprocess.run(["notify-send", "-a", "pix2tex", title, body], check=False)
    except OSError:
        log("%s: %s" % (title, body))


def ocr(data):
    """Ask the daemon; fall back to loading the model inline if it's down."""
    try:
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        conn.settimeout(180)
        conn.connect(SOCK_PATH)
    except OSError as e:
        log("daemon unavailable (%s), loading model inline — this is slow" % e)
        return load_model()(data)

    with conn:
        send_msg(conn, data)
        reply = recv_msg(conn).decode("utf-8")

    status, _, payload = reply.partition("\t")
    if status != "OK":
        raise RuntimeError(payload)
    return payload


def purge_recent_screenshot(max_age=120):
    """Delete PNGs GNOME saved in the last couple of minutes."""
    if not os.path.isdir(SHOTS_DIR):
        return
    now = time.time()
    for name in os.listdir(SHOTS_DIR):
        if not name.lower().endswith(".png"):
            continue
        path = os.path.join(SHOTS_DIR, name)
        try:
            if now - os.path.getmtime(path) < max_age:
                os.unlink(path)
                log("purged", path)
        except OSError:
            pass


def run_client(purge=False):
    data = clipboard_image()
    if not data:
        notify("pix2tex", "No image in the clipboard. Capture one with Shift+PrtScr first.")
        return 1

    try:
        latex = ocr(data)
    except Exception as e:
        notify("pix2tex failed", str(e))
        log(e)
        return 1

    latex = latex.strip()
    if not latex:
        notify("pix2tex", "No formula recognised")
        return 1

    try:
        subprocess.run(["wl-copy"], input=latex.encode("utf-8"), check=False)
    except OSError:
        notify("pix2tex", "wl-copy missing — install wl-clipboard")
        print(latex)
        return 1

    if purge:
        purge_recent_screenshot()
    notify("Copied to clipboard", latex)
    print(latex)
    return 0


# --- self test -------------------------------------------------------------

def run_self_test():
    from PIL import Image, ImageDraw
    img = Image.new("L", (260, 70), 255)
    ImageDraw.Draw(img).text((12, 25), "E = mc^2", fill=0)
    buf = io.BytesIO()
    img.save(buf, format="PNG")

    try:
        out = ocr(buf.getvalue())
    except Exception as e:
        print("    [x] pipeline failed: %s" % e)
        return 1

    print("    [ok] pipeline ran, model returned: %r" % out)
    print("    (smoke test only — proves the pipeline works, not accuracy)")
    return 0


if __name__ == "__main__":
    if "--daemon" in sys.argv:
        run_daemon()
    elif "--self-test" in sys.argv:
        sys.exit(run_self_test())
    else:
        sys.exit(run_client(purge="--purge" in sys.argv))
PYEOF

chmod +x "$SNIP"
info "installed $SNIP"

# -------------------------------------------------------- systemd service --

step "Systemd user service"
mkdir -p "$UNIT_DIR"

cat > "$UNIT_DIR/$UNIT_NAME" <<EOF
[Unit]
Description=pix2tex OCR daemon (keeps the model warm)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$SNIP --daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

# The client needs the session variables; make sure the user manager has them.
systemctl --user import-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_CURRENT_DESKTOP 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable "$UNIT_NAME" >/dev/null 2>&1 || true
systemctl --user restart "$UNIT_NAME"

info "waiting for the model to load..."
for _ in $(seq 1 60); do
    [[ -S "${XDG_RUNTIME_DIR:-/tmp}/pix2tex.sock" ]] && break
    sleep 2
done

if [[ -S "${XDG_RUNTIME_DIR:-/tmp}/pix2tex.sock" ]]; then
    info "daemon up"
else
    warn "socket not there yet — check: journalctl --user -u $UNIT_NAME -n 40"
fi

# ------------------------------------------------------------------ verify --

verify || die "install finished but verification failed"

cat <<EOF

${B}One manual step left${R} — bind the hotkey:

  Settings -> Keyboard -> View and Customize Shortcuts -> Custom Shortcuts
    Name:     pix2tex snip
    Command:  $SNIP
    Shortcut: Super+L   (or whatever you prefer)

${B}Then the flow is${R}:

  1. Shift+PrtScr   drag over the formula   (GNOME's own capture)
  2. Super+L        LaTeX lands in your clipboard, notification confirms
  3. Ctrl+V         into your notes

GNOME also saves a PNG to ~/Pictures/Screenshots. To have those cleaned up
automatically, use this as the hotkey command instead:

  $SNIP --purge

Useful commands:

  systemctl --user status $UNIT_NAME       is the daemon alive
  journalctl --user -u $UNIT_NAME -f       watch it work
  $0 --check                               re-run the end-to-end test

EOF
