#!/usr/bin/env bash
# source_me_first_4_uv.sh - uv-based installer (sourced)
#
# This file is intended to be sourced, not executed. Source it into your shell to
# define the following functions:
#   install_uv [options]        Create a local virtualenv (default ./.venv) and install deps
#   activate_venv (alias: activate-venv)
#   install_activate_func       Append activate_venv and alias activate-venv to ~/.bashrc
#
# If you run this file directly (./source_me_first_4_uv.sh) it will print a short error and exit.

# --------------------------- Execution guard ---------------------------
# If executed directly, print an error and usage hint then exit.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cat <<'MSG' >&2
This file is intended to be sourced, not executed.

Usage:
  source ./source_me_first_4_uv.sh
  install_uv --help        # show installer help after sourcing

Sourcing defines helper functions in your current shell. Exiting now.
MSG
  exit 1
fi

# --------------------------- Defaults ---------------------------------
DEFAULT_VENV_DIR=".venv"
DEFAULT_PYTHON="${PYTHON:-python3}"
DEFAULT_UV_BIN="${UV_BIN:-uv}"
DEFAULT_KERNEL_NAME="ece4076"
DEFAULT_DISPLAY_NAME="ECE4076"

# --------------------------- Help -------------------------------------
install_uv_help() {
  cat <<'HELP'
install_uv [options]

Create or reuse a local virtual environment and install dependencies using uv.

Options:
  --cpu-torch             Use CPU-only PyTorch wheels (sets --torch-backend=cpu)
  --torch-backend <val>   Pass a specific value to uv pip sync --torch-backend
  --venv-dir <path>       Path to virtualenv (default: ./.venv)
  --python <interpreter>  Python interpreter to use to create the venv (default: python3)
  --uv-bin <path>         Path to the uv binary (default: uv)
  --install-shell-func    Append activate_venv() and alias activate-venv to ~/.bashrc
  -h, --help              Show this help

Examples:
  install_uv --cpu-torch
  install_uv --venv-dir .venv --python python3.11

HELP
}


# --------------------------- Activation Helper ------------------------
# Finds candidate virtualenv directories in the current folder and offers to
# activate one. This function is suitable for appending to ~/.bashrc.
activate_venv() {
  local candidates=()
  local d
  for d in ./*; do
    [ -e "$d" ] || continue
    if [ -d "$d" ] && ( [ -f "$d/bin/activate" ] || [ -f "$d/Scripts/activate" ] || [ -f "$d/pyvenv.cfg" ] ); then
      candidates+=("$d")
    fi
  done

  # Prefer .venv if present
  if [ -d .venv ]; then
    # ensure .venv is first in list (if present)
    local found=false newlist=(.venv)
    for d in "${candidates[@]}"; do
      if [ "$d" = ".venv" ]; then found=true; continue; fi
      newlist+=("$d")
    done
    if [ "$found" = true ]; then candidates=("${newlist[@]}"); fi
  fi

  if [ ${#candidates[@]} -eq 0 ]; then
    echo "No local virtual environments found in $(pwd)"
    return 1
  fi

  echo "Local virtual environments:"
  local i=1
  for d in "${candidates[@]}"; do
    printf "%3d) %s\n" "$i" "$d"
    i=$((i+1))
  done

  local sel
  read -rp "Choose a virtualenv to activate (1-${#candidates[@]}, q to cancel) [1]: " sel
  if [ -z "$sel" ]; then sel=1; fi
  if [ "$sel" = "q" ] || [ "$sel" = "Q" ]; then
    echo "Cancelled"
    return 0
  fi
  if ! printf '%s\n' "$sel" | grep -Eq '^[0-9]+$'; then
    echo "Invalid selection"
    return 1
  fi
  if [ "$sel" -lt 1 ] || [ "$sel" -gt ${#candidates[@]} ]; then
    echo "Selection out of range"
    return 1
  fi

  local target="${candidates[$((sel-1))]}"
  if [ -f "$target/bin/activate" ]; then
    # shellcheck disable=SC1090
    source "$target/bin/activate"
    echo "Activated $target"
    return 0
  elif [ -f "$target/Scripts/activate" ]; then
    # shellcheck disable=SC1090
    source "$target/Scripts/activate"
    echo "Activated $target"
    return 0
  else
    echo "No activation script found in $target"
    return 1
  fi
}

# Provide short, hyphenated alias for convenience
alias activate-venv='activate_venv'


# --------------------------- Install to ~/.bashrc ---------------------
# Appends the activate_venv function to ~/.bashrc if not already present.
install_activate_func() {
  local rcfile="${HOME}/.bashrc"
  if [ ! -w "$rcfile" ] && [ ! -w "${HOME}" ]; then
    echo "Cannot write to $rcfile; check permissions or install manually."
    return 1
  fi

  if grep -q "^activate_venv()" "$rcfile" 2>/dev/null; then
    echo "activate_venv already present in $rcfile"
    return 0
  fi

  cat >> "$rcfile" <<'BASHFUNC'
# BEGIN activate_venv (added by source_me_first_4_uv.sh)
activate_venv() {
  local candidates=()
  local d
  for d in ./*; do
    [ -e "$d" ] || continue
    if [ -d "$d" ] && ( [ -f "$d/bin/activate" ] || [ -f "$d/Scripts/activate" ] || [ -f "$d/pyvenv.cfg" ] ); then
      candidates+=("$d")
    fi
  done
  if [ -d .venv ]; then
    local found=false newlist=(.venv)
    for d in "${candidates[@]}"; do
      if [ "$d" = ".venv" ]; then found=true; continue; fi
      newlist+=("$d")
    done
    if [ "$found" = true ]; then candidates=("${newlist[@]}"); fi
  fi
  if [ ${#candidates[@]} -eq 0 ]; then
    echo "No local virtual environments found in $(pwd)"
    return 1
  fi
  echo "Local virtual environments:"
  local i=1
  for d in "${candidates[@]}"; do
    printf "%3d) %s\n" "$i" "$d"
    i=$((i+1))
  done
  local sel
  read -rp "Choose a virtualenv to activate (1-${#candidates[@]}, q to cancel) [1]: " sel
  if [ -z "$sel" ]; then sel=1; fi
  if [ "$sel" = "q" ] || [ "$sel" = "Q" ]; then
    echo "Cancelled"
    return 0
  fi
  if ! printf '%s\n' "$sel" | grep -Eq '^[0-9]+$'; then
    echo "Invalid selection"
    return 1
  fi
  if [ "$sel" -lt 1 ] || [ "$sel" -gt ${#candidates[@]} ]; then
    echo "Selection out of range"
    return 1
  fi
  local target="${candidates[$((sel-1))]}"
  if [ -f "$target/bin/activate" ]; then
    # shellcheck disable=SC1090
    source "$target/bin/activate"
    echo "Activated $target"
    return 0
  elif [ -f "$target/Scripts/activate" ]; then
    # shellcheck disable=SC1090
    source "$target/Scripts/activate"
    echo "Activated $target"
    return 0
  else
    echo "No activation script found in $target"
    return 1
  fi
}
# END activate_venv

alias activate-venv='activate_venv'
BASHFUNC

  echo "Appended activate_venv and alias activate-venv to $rcfile"
  return 0
}


# --------------------------- Main installer ---------------------------
# This is the function users should call after sourcing this file.
install_uv() {
  local TORCH_BACKEND=""
  local INSTALL_SHELL_FUNC=false
  local VENV_DIR="$DEFAULT_VENV_DIR"
  local PYTHON_BIN="$DEFAULT_PYTHON"
  local UV_BIN="$DEFAULT_UV_BIN"
  local KERNEL_NAME="$DEFAULT_KERNEL_NAME"
  local DISPLAY_NAME="$DEFAULT_DISPLAY_NAME"

  # parse args
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cpu-torch)
        TORCH_BACKEND="cpu"; shift;;
      --torch-backend)
        if [ -n "${2-}" ]; then TORCH_BACKEND="$2"; shift 2; else echo "--torch-backend requires a value"; return 1; fi;;
      --venv-dir|--venv)
        if [ -n "${2-}" ]; then VENV_DIR="$2"; shift 2; else echo "--venv-dir requires a path"; return 1; fi;;
      --python)
        if [ -n "${2-}" ]; then PYTHON_BIN="$2"; shift 2; else echo "--python requires a value"; return 1; fi;;
      --uv-bin)
        if [ -n "${2-}" ]; then UV_BIN="$2"; shift 2; else echo "--uv-bin requires a value"; return 1; fi;;
      --install-shell-func)
        INSTALL_SHELL_FUNC=true; shift;;
      -h|--help)
        install_uv_help; return 0;;
      *) echo "Unknown option: $1"; install_uv_help; return 1;;
    esac
  done

  printf '== ECE4076 Installation (uv) ==\n'
  printf '  venv dir: %s\n' "$VENV_DIR"
  printf '  python:   %s\n' "$PYTHON_BIN"
  printf '  uv bin:   %s\n' "$UV_BIN"
  [ -n "$TORCH_BACKEND" ] && printf '  torch backend: %s\n' "$TORCH_BACKEND"

  if ! command -v "$UV_BIN" >/dev/null 2>&1; then
    echo "ERROR: 'uv' not found. Install with: pipx install uv or pip install --user uv"
    return 1
  fi

  if [ ! -f requirements.txt ]; then
    echo "ERROR: requirements.txt not found in $(pwd)"
    return 1
  fi

  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "ERROR: Python interpreter '$PYTHON_BIN' not found"
    return 1
  fi

  local PY_VER
  PY_VER="$($PYTHON_BIN -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')"
  printf 'Found Python %s (interpreter: %s)\n' "$PY_VER" "$PYTHON_BIN"

  # Create venv if missing
  if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" -o -f "$VENV_DIR/pyvenv.cfg" ]; then
    echo "Using existing virtual environment at: $VENV_DIR"
  else
    echo "Creating virtual environment ($VENV_DIR) using uv..."
    "$UV_BIN" venv -p "$PYTHON_BIN" "$VENV_DIR" || { echo "uv venv failed"; return 1; }
    echo "Virtual environment created at: $VENV_DIR"
  fi

  # Ensure venv python executable path
  local VENV_PYTHON="$VENV_DIR/bin/python"
  if [ ! -x "$VENV_PYTHON" ]; then VENV_PYTHON="$(pwd)/$VENV_PYTHON"; fi

  # Ensure pip exists in venv
  if "$VENV_PYTHON" -m pip --version >/dev/null 2>&1; then
    echo "pip present in venv"
  else
    echo "Bootstrapping pip in the venv..."
    if "$VENV_PYTHON" -m ensurepip --upgrade >/dev/null 2>&1; then
      echo "ensurepip succeeded"
    else
      local TMP_GET_PIP
      TMP_GET_PIP="$(mktemp -t get-pip.XXXXXX)" || { echo "mktemp failed"; return 1; }
      if command -v curl >/dev/null 2>&1; then
        curl -sS https://bootstrap.pypa.io/get-pip.py -o "$TMP_GET_PIP" || { echo "curl failed"; rm -f "$TMP_GET_PIP"; return 1; }
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP_GET_PIP" https://bootstrap.pypa.io/get-pip.py || { echo "wget failed"; rm -f "$TMP_GET_PIP"; return 1; }
      else
        echo "ERROR: cannot download get-pip.py because neither curl nor wget is available"
        return 1
      fi
      "$VENV_PYTHON" "$TMP_GET_PIP" || { echo "get-pip.py failed"; rm -f "$TMP_GET_PIP"; return 1; }
      rm -f "$TMP_GET_PIP"
    fi
  fi

  echo "Upgrading pip, setuptools and wheel in the venv..."
  "$VENV_PYTHON" -m pip install --upgrade pip setuptools wheel || { echo "pip upgrade failed"; return 1; }

  # Prepare lockfile
  local LOCKFILE="uv.lock" PYLOCK="pylock.toml"
  if [ -f "$LOCKFILE" ] || [ -f "$PYLOCK" ]; then
    echo "Found lockfile; will use it"
  else
    echo "No lockfile found; compiling requirements.txt -> pylock.toml"
    if "$UV_BIN" pip compile requirements.txt --format pylock.toml -o "$PYLOCK"; then
      echo "Generated $PYLOCK"
    else
      echo "uv pip compile failed; attempting uv lock as fallback (best-effort)"
      "$UV_BIN" lock || true
    fi
  fi

  # Sync packages into the venv
  echo "Syncing packages into venv with uv pip sync..."
  if [ -n "$TORCH_BACKEND" ]; then
    if [ -f "$LOCKFILE" ]; then
      "$UV_BIN" pip sync "$LOCKFILE" --python "$VENV_PYTHON" --torch-backend "$TORCH_BACKEND" || { echo "uv pip sync failed"; return 1; }
    elif [ -f "$PYLOCK" ]; then
      "$UV_BIN" pip sync "$PYLOCK" --python "$VENV_PYTHON" --torch-backend "$TORCH_BACKEND" || { echo "uv pip sync failed"; return 1; }
    else
      echo "No lockfile found, falling back to pip install -r requirements.txt"
      "$VENV_PYTHON" -m pip install -r requirements.txt || { echo "pip install failed"; return 1; }
    fi
  else
    if [ -f "$LOCKFILE" ]; then
      "$UV_BIN" pip sync "$LOCKFILE" --python "$VENV_PYTHON" || { echo "uv pip sync failed"; return 1; }
    elif [ -f "$PYLOCK" ]; then
      "$UV_BIN" pip sync "$PYLOCK" --python "$VENV_PYTHON" || { echo "uv pip sync failed"; return 1; }
    else
      echo "No lockfile found, falling back to pip install -r requirements.txt"
      "$VENV_PYTHON" -m pip install -r requirements.txt || { echo "pip install failed"; return 1; }
    fi
  fi

  echo "Packages installed"

  echo "Installing ipykernel and registering Jupyter kernel..."
  "$VENV_PYTHON" -m pip install --upgrade ipykernel || { echo "ipykernel install failed"; return 1; }
  "$VENV_PYTHON" -m ipykernel install --user --name "$DEFAULT_KERNEL_NAME" --display-name "$DEFAULT_DISPLAY_NAME" || { echo "ipykernel registration failed"; return 1; }

  if [ "$INSTALL_SHELL_FUNC" = true ]; then
    install_activate_func || { echo "failed to install shell function"; return 1; }
  fi

  echo "Installation complete. Activate with: source $VENV_DIR/bin/activate"
  return 0
}


# --------------------------- Sourced guidance -------------------------
# When this file is sourced without arguments provide a short usage hint.
if [ "$#" -eq 0 ]; then
  cat <<'GUIDE'
source_me_first_4_uv.sh loaded — quick start

1) Create and install dependencies (CPU PyTorch example):
     install_uv --cpu-torch

2) Use a different Python or venv path:
     install_uv --venv-dir .venv --python python3.11

3) Activate a local venv interactively:
     activate-venv   # alias for activate_venv()

4) Make activate-venv available in new shells:
     install_uv --install-shell-func

5) See full installer help:
     install_uv --help

GUIDE
fi

# End of file - functions are defined when this file is sourced.
