#!/usr/bin/env bash
# source_me_first_4_uv.sh - uv-based installer (sourced)
#
# This file is intended to be sourced, not executed. Source it into your shell to
# define the following functions:
#   install_uv [options]        Create a local virtualenv (default ./.venv) and install deps
#   activate_venv (alias: activate-venv)
#   install_activate_func       Write activate_venv helper to ~/.local/etc/bash.d and print a one-time
#                               snippet to enable it in your shell rc (the script does NOT edit ~/.bashrc)
#
# If you run this file directly (./source_me_first_4_uv.sh) it will print a short error and exit.

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
  --install-shell-func    Install activate_venv helper to ~/.local/etc/bash.d and print one-time enable snippet
  --no-gpu-detect         Disable automatic GPU detection for selecting torch backend
  --dry-run               Preview the uv pip sync plan and prompt before installing
  -y, --yes               Assume yes for prompts (useful for CI)
  --auto-install-python   If the requested Python is missing, attempt to install it via pyenv (may prompt)
  -h, --help              Show this help

Examples:
  install_uv --cpu-torch
  install_uv --venv-dir .venv --python python3.11

HELP
}

# --------------------------- Execution guard ---------------------------
# If the script is executed rather than sourced, print usage guidance and help.
_sourced=0
if [ -n "${BASH_SOURCE-}" ]; then
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    _sourced=1
  fi
else
  (return 0 2>/dev/null) && _sourced=1 || _sourced=0
fi
if [ "$_sourced" -ne 1 ]; then
  cat <<'MSG' >&2
This file is intended to be sourced, not executed.

Usage:
  source ./source_me_first_4_uv.sh
  . ./source_me_first_4_uv.sh

You can then call: install_uv --help
MSG
  echo
  install_uv_help
  exit 0
fi

# --------------------------- Defaults ---------------------------------
DEFAULT_VENV_DIR=".venv"
DEFAULT_PYTHON="${PYTHON:-python3}"
DEFAULT_UV_BIN="${UV_BIN:-uv}"
DEFAULT_KERNEL_NAME="ece4076"
DEFAULT_DISPLAY_NAME="ECE4076"

# --------------------------- Installer ID -----------------------------
# A short identifier (git short SHA when available, else a UTC timestamp)
# Printed when this file is sourced to help diagnose which copy/version is loaded.
INSTALLER_ID="$(date -u +%Y%m%dT%H%M%SZ)"
if command -v git >/dev/null 2>&1; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _gsha=$(git rev-parse --short HEAD 2>/dev/null || true)
    if [ -n "$_gsha" ]; then
      INSTALLER_ID="git:$_gsha"
    fi
    unset _gsha
  fi
fi

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
  --install-shell-func    Install activate_venv helper to ~/.local/etc/bash.d and print one-time enable snippet
  --no-gpu-detect         Disable automatic GPU detection for selecting torch backend
  --dry-run               Preview the uv pip sync plan and prompt before installing
  -y, --yes               Assume yes for prompts (useful for CI)
  --auto-install-python   If the requested Python is missing, attempt to install it via pyenv (may prompt)
  -h, --help              Show this help

Examples:
  install_uv --cpu-torch
  install_uv --venv-dir .venv --python python3.11

HELP
}

# List available python executables and pyenv versions (helper)
list_available_pythons() {
  echo
  echo "Searching for python executables in PATH and common locations..."
  local old_nullglob
  shopt -q nullglob 2>/dev/null && old_nullglob=1 || old_nullglob=0
  shopt -s nullglob 2>/dev/null || true

  local candidates=()
  local p
  # Use which -a when available to find PATH entries
  if command -v which >/dev/null 2>&1; then
    # try a few common names
    for p in $(which -a python python3 python2 2>/dev/null | awk '!x[$0]++'); do
      [ -x "$p" ] || continue
      candidates+=("$p")
    done
  fi

  # add common system locations, pyenv installs, local venvs
  for p in /usr/bin/python* /usr/local/bin/python* /opt/homebrew/bin/python* /opt/python*/bin/python* "$HOME/.pyenv/versions/"*/bin/python* "$HOME/.pyenv/shims/python"* "$HOME/.local/bin/python*"; do
    [ -x "$p" ] || continue
    candidates+=("$p")
  done

  # include local venvs in cwd
  for p in ./.venv*/bin/python* ./.venv*/Scripts/python*; do
    [ -x "$p" ] || continue
    candidates+=("$p")
  done

  # deduplicate preserving order
  local seen=()
  local uniq_list=()
  for p in "${candidates[@]}"; do
    local skip=0
    for q in "${seen[@]}"; do
      if [ "$p" = "$q" ]; then skip=1; break; fi
    done
    if [ $skip -eq 0 ]; then
      seen+=("$p")
      uniq_list+=("$p")
    fi
  done

  if [ ${#uniq_list[@]} -eq 0 ]; then
    echo "  (no python executables found)"
  else
    local i=0
    for p in "${uniq_list[@]}"; do
      i=$((i+1))
      local ver
      ver="$($p --version 2>&1 || true)"
      printf "%3d) %-45s %s\n" "$i" "$p" "$ver"
    done
  fi

  if command -v pyenv >/dev/null 2>&1; then
    echo
    echo "pyenv installed versions:"
    pyenv versions --bare 2>/dev/null | sed -e 's/^/  - /' || true
  fi

  if [ $old_nullglob -eq 0 ]; then
    shopt -u nullglob 2>/dev/null || true
  fi
  echo
}


# --------------------------- Activation Helper ------------------------
# Finds candidate virtualenv directories in the current folder and offers to
# activate one. This function is suitable for being installed as a shell helper
# (the installer writes it to ~/.local/etc/bash.d and prints a one-time snippet
# that you can add to your shell rc to enable it).
activate_venv() {
  local candidates=()
  local d nd
  # include both visible and hidden directories (e.g. .venv)
  for d in ./* ./.?*; do
    [ -e "$d" ] || continue
    # skip '.' and '..' entries that may appear from the .?* glob
    case "$d" in
      .|./.|../|./..)
        continue
        ;;
    esac
    # normalize to remove leading './' for nicer display and comparison
    nd="${d#./}"
    if [ -d "$d" ] && ( [ -f "$d/bin/activate" ] || [ -f "$d/Scripts/activate" ] || [ -f "$d/pyvenv.cfg" ] ); then
      candidates+=("$nd")
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


# --------------------------- Install activate_venv helper ---------------------
# Instead of editing shell rc files, write the helper to
# ~/.local/etc/bash.d/50-activate-venv.sh and print a one-time snippet the
# user can add to their shell rc (the script does NOT edit ~/.bashrc).
install_activate_func() {
  local auto_confirm="${1:-}"
  local local_dir="${HOME}/.local/etc/bash.d"
  local target_file="$local_dir/50-activate-venv.sh"

  if ! mkdir -p "$local_dir" 2>/dev/null; then
    echo "Failed to create directory: $local_dir"; return 1
  fi

  if [ -f "$target_file" ]; then
    echo "File already exists: $target_file"
    if [ "$auto_confirm" != "true" ]; then
      read -rp "Overwrite $target_file? [y/N]: " _ans
      if ! printf '%s' "${_ans:-N}" | grep -Eq '^[Yy]'; then
        echo "Left existing file in place. To enable the helper, add the snippet shown below to your shell rc (e.g. ~/.bashrc)."
        echo
        cat <<'SNIP'
# Add once to your shell rc (e.g. ~/.bashrc) to source the activate-venv helper
if [ -f "$HOME/.local/etc/bash.d/50-activate-venv.sh" ]; then
  source "$HOME/.local/etc/bash.d/50-activate-venv.sh"
fi
SNIP
        return 0
      fi
    fi
    local backup="$target_file.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    cp -a "$target_file" "$backup" 2>/dev/null || true
    echo "Backed up existing file to: $backup"
  fi

  local tmpf
  tmpf=$(mktemp -t activate_venv.XXXXXX) || { echo "mktemp failed"; return 1; }
  cat > "$tmpf" <<'SH'
# This file defines the activate_venv helper used by the ECE4076 installer.
activate_venv() {
  local candidates=()
  local d nd
  for d in ./* ./.?*; do
    [ -e "$d" ] || continue
    case "$d" in
      .|./.|../|./..)
        continue
        ;;
    esac
    nd="${d#./}"
    if [ -d "$d" ] && ( [ -f "$d/bin/activate" ] || [ -f "$d/Scripts/activate" ] || [ -f "$d/pyvenv.cfg" ] ); then
      candidates+=("$nd")
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

alias activate-venv='activate_venv'
SH
  mv "$tmpf" "$target_file" || { echo "Failed to move file into place"; rm -f "$tmpf"; return 1; }
  chmod 644 "$target_file" || true

  echo "Wrote activate_venv helper to: $target_file"
  echo
  echo "To enable this helper in new shells, add the following snippet to your shell rc (only needs to be done once):"
  echo
  cat <<'SNIP'
# Add once to your shell rc (e.g. ~/.bashrc) to source the activate-venv helper
if [ -f "$HOME/.local/etc/bash.d/50-activate-venv.sh" ]; then
  source "$HOME/.local/etc/bash.d/50-activate-venv.sh"
fi
SNIP

  echo
  echo "Alternatively, to source all snippets in ~/.local/etc/bash.d, add this instead:"
  echo 'for f in "$HOME/.local/etc/bash.d"/*.sh; do [ -r "$f" ] && source "$f"; done'
  return 0
}


# --------------------------- Main installer ---------------------------
# This is the function users should call after sourcing this file.
install_uv() {
  local TORCH_BACKEND=""
  local INSTALL_SHELL_FUNC=false
  local AUTO_GPU_DETECT=true
  local DRY_RUN=false
  local AUTO_YES=false
  local APPLY=false
  local AUTO_INSTALL_PYTHON=false
  local CHECK_LOCK=false
  local UPDATE_LOCK=false
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
      --no-gpu-detect)
        AUTO_GPU_DETECT=false; shift;;
      --python)
        if [ -n "${2-}" ]; then PYTHON_BIN="$2"; shift 2; else echo "--python requires a value"; return 1; fi;;
      --uv-bin)
        if [ -n "${2-}" ]; then UV_BIN="$2"; shift 2; else echo "--uv-bin requires a value"; return 1; fi;;
      --install-shell-func)
        INSTALL_SHELL_FUNC=true; shift;;
      --dry-run)
        DRY_RUN=true; shift;;
      --apply)
        APPLY=true; shift;;
      --check-lock)
        CHECK_LOCK=true; shift;;
      --update-lock)
        UPDATE_LOCK=true; shift;;
      --auto-install-python)
        AUTO_INSTALL_PYTHON=true; shift;;
      -y|--yes)
        AUTO_YES=true; shift;;
      -h|--help)
        install_uv_help; return 0;;
      *) echo "Unknown option: $1"; install_uv_help; return 1;;
    esac
  done

  # If the user only requested the shell helper, perform that action and exit
  # immediately. This avoids running the full install flow when the user only
  # wants the activation helper installed.
  if [ "$INSTALL_SHELL_FUNC" = true ]; then
    if [ "$AUTO_YES" = true ]; then
      install_activate_func true || { echo "failed to install shell function"; return 1; }
    else
      install_activate_func || { echo "failed to install shell function"; return 1; }
    fi
    return 0
  fi

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
    echo "ERROR: Python interpreter '$PYTHON_BIN' not found."

    # Try to detect a requested version from the interpreter name (e.g. python3.11)
    local _py_base _py_version _major _minor
    _py_base="$(basename "$PYTHON_BIN")"
    _py_version=""
    if [[ "$_py_base" =~ ^python([0-9]+)(\.[0-9]+)? ]]; then
      _major="${BASH_REMATCH[1]}"
      _minor="${BASH_REMATCH[2]}"
      if [ -n "$_minor" ]; then
        _minor="${_minor#.}"
        _py_version="${_major}.${_minor}"
      else
        _py_version="${_major}"
      fi
    elif [[ "$_py_base" =~ ^([0-9]+\.[0-9]+)$ ]]; then
      _py_version="${BASH_REMATCH[1]}"
    fi

    # Helper: list available python executables and suggest closest match
    list_available_pythons

    if [ -n "$_py_version" ]; then
      echo
      echo "Requested Python version inferred from '$PYTHON_BIN': $_py_version"
      if [ "$AUTO_INSTALL_PYTHON" = true ]; then
        echo "Auto-install requested: attempting to install with pyenv..."
        # Ensure pyenv present or offer to install it
        if ! command -v pyenv >/dev/null 2>&1; then
          if [ "$AUTO_YES" = true ]; then
            _do_install_pyenv=yes
          else
            read -rp "pyenv not found. Install pyenv now? [y/N]: " _ans
            if printf '%s' "${_ans:-N}" | grep -Eq '^[Yy]'; then _do_install_pyenv=yes; fi
          fi
          if [ "${_do_install_pyenv:-}" = "yes" ]; then
            echo "Installing pyenv (this will clone into ~/.pyenv)..."
            if command -v curl >/dev/null 2>&1; then
              curl -sS https://pyenv.run | bash || { echo "pyenv installer failed"; return 1; }
            elif command -v wget >/dev/null 2>&1; then
              wget -qO- https://pyenv.run | bash || { echo "pyenv installer failed"; return 1; }
            else
              echo "Cannot download pyenv installer (curl or wget required)"; return 1
            fi
            # Export pyenv into current shell session so we can use it immediately
            export PATH="$HOME/.pyenv/bin:$PATH"
            if command -v pyenv >/dev/null 2>&1; then
              # shellcheck disable=SC1091
              eval "$(pyenv init -)" 2>/dev/null || true
            fi
          else
            echo "pyenv not installed; aborting auto-install of Python."
            return 1
          fi
        fi

        # At this point pyenv should be available. Find a matching full version
        local _full_version
        _full_version=$(pyenv install --list 2>/dev/null | sed -e 's/^[[:space:]]*//' | grep -E "^${_py_version}\\.[0-9]+$" | tail -1 || true)
        if [ -z "$_full_version" ]; then
          # try more general match
          _full_version=$(pyenv install --list 2>/dev/null | sed -e 's/^[[:space:]]*//' | grep -E "^${_py_version}" | tail -1 || true)
        fi
        if [ -z "$_full_version" ]; then
          echo "Could not locate a pyenv-distributable Python matching ${_py_version}."
          echo "Run 'pyenv install --list' to view available versions, then install manually."
          return 1
        fi

        echo "Installing Python ${_full_version} via pyenv (may require development build deps)..."
        # Use -s to skip if already installed (pyenv may support -s)
        if pyenv install -s "$_full_version"; then
          echo "Python ${_full_version} installed via pyenv"
        else
          echo "pyenv install failed. Ensure build dependencies are present. See https://github.com/pyenv/pyenv/wiki#suggested-build-environment";
          return 1
        fi

        # Make the installed interpreter available in this shell
        export PATH="$HOME/.pyenv/bin:$PATH"
        eval "$(pyenv init -)" 2>/dev/null || true
        pyenv rehash 2>/dev/null || true

        # Use the newly installed interpreter path for subsequent operations
        local _installed_python
        _installed_python=$(pyenv which python 2>/dev/null || true)
        if [ -n "$_installed_python" ] && [ -x "$_installed_python" ]; then
          PYTHON_BIN="$_installed_python"
          echo "Using Python interpreter: $PYTHON_BIN"
        else
          # fallback: try to construct path from pyenv root
          local _pfx
          _pfx=$(pyenv prefix "$_full_version" 2>/dev/null || true)
          if [ -n "$_pfx" ] && [ -x "$_pfx/bin/python" ]; then
            PYTHON_BIN="$_pfx/bin/python"
            echo "Using Python interpreter: $PYTHON_BIN"
          else
            echo "Failed to locate the installed Python executable."
            return 1
          fi
        fi

        # Continue the install using the newly installed interpreter
      else
        # Not auto-installing: provide instructions
        if command -v pyenv >/dev/null 2>&1; then
          echo "pyenv is installed. To install a matching Python, run:"
          echo
          echo "  pyenv install --list  # find a full version matching ${_py_version}, e.g. ${_py_version}.X"
          echo "  pyenv install <full-version>"
          echo "  pyenv local <full-version>"
          echo
          echo "Then re-run: install_uv --python ${PYTHON_BIN}"
        else
          echo "Install pyenv and then install a matching Python version. Example:" 
          echo
          echo "  # install pyenv (one-line installer)"
          echo "  curl https://pyenv.run | bash"
          echo "  # follow the post-install instructions printed by the installer (add pyenv to PATH / shell init)"
          echo "  pyenv install --list  # choose a full version matching ${_py_version}, e.g. ${_py_version}.X"
          echo "  pyenv install <full-version>"
          echo "  pyenv local <full-version>"
          echo
          echo "Then re-run: install_uv --python ${PYTHON_BIN}"
        fi
        return 1
      fi
    else
      echo
      echo "Please install a suitable Python interpreter named '${PYTHON_BIN}' or provide an absolute path to a Python executable."
      echo "You can use pyenv to install interpreters: https://github.com/pyenv/pyenv"
      return 1
    fi
  fi

  local PY_VER
  PY_VER="$($PYTHON_BIN -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')"
  printf 'Found Python %s (interpreter: %s)\n' "$PY_VER" "$PYTHON_BIN"

  # GPU detection - simple heuristics
  local DETECTED_GPU="none"
  if [ "$AUTO_GPU_DETECT" = true ]; then
    if command -v nvidia-smi >/dev/null 2>&1; then
      DETECTED_GPU="nvidia"
    elif command -v rocminfo >/dev/null 2>&1 || command -v rocm-smi >/dev/null 2>&1; then
      DETECTED_GPU="amd"
    elif command -v lspci >/dev/null 2>&1 && lspci | grep -i intel | grep -i vga >/dev/null 2>&1; then
      # Intel GPUs are less commonly supported by PyTorch; treat as intel
      DETECTED_GPU="intel"
    else
      DETECTED_GPU="cpu"
    fi
  else
    DETECTED_GPU="undetected"
  fi
  printf 'Detected GPU: %s\n' "$DETECTED_GPU"

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

  echo "Upgrading pip in the venv..."
  # Avoid upgrading setuptools here because some packages (e.g. torch) may
  # require an upper-bound on setuptools. Let the lockfile / uv pip sync
  # control the setuptools version to prevent resolver conflicts.
  "$VENV_PYTHON" -m pip install --upgrade pip || { echo "pip upgrade failed"; return 1; }

  # Prepare lockfile
  local LOCKFILE="uv.lock" PYLOCK="pylock.toml"

  # Determine selected torch backend (user override takes precedence)
  local SELECTED_TORCH_BACKEND
  if [ -n "$TORCH_BACKEND" ]; then
    SELECTED_TORCH_BACKEND="$TORCH_BACKEND"
  else
    case "$DETECTED_GPU" in
      nvidia) SELECTED_TORCH_BACKEND="auto" ;;
      amd) SELECTED_TORCH_BACKEND="auto" ;;
      intel) SELECTED_TORCH_BACKEND="cpu" ;;
      cpu) SELECTED_TORCH_BACKEND="cpu" ;;
      undetected) SELECTED_TORCH_BACKEND="cpu" ;;
      *) SELECTED_TORCH_BACKEND="cpu" ;;
    esac
  fi
  printf 'Selected torch backend for compile/sync: %s\n' "$SELECTED_TORCH_BACKEND"

  # Optionally update the repo pylock (user requested) before proceeding.
  if [ "$UPDATE_LOCK" = true ]; then
    echo "Updating pylock.toml using backend: $SELECTED_TORCH_BACKEND"
    UV_TORCH_BACKEND="$SELECTED_TORCH_BACKEND" "$UV_BIN" pip compile requirements.txt --format pylock.toml -o "$PYLOCK" || {
      echo "uv pip compile failed while updating lock"; return 1;
    }
    echo "pylock.toml regenerated. Please review and commit the file if desired."
  fi

  # Always (re)compile requirements.txt to pylock.toml using the selected backend
  echo "Compiling requirements.txt -> $PYLOCK (torch backend: $SELECTED_TORCH_BACKEND)"
  UV_TORCH_BACKEND="$SELECTED_TORCH_BACKEND" "$UV_BIN" pip compile requirements.txt --format pylock.toml -o "$PYLOCK" || {
    echo "uv pip compile failed; attempting uv lock as fallback (best-effort)";
    "$UV_BIN" lock || true;
  }

  # If requested, compare freshly generated pylock with repo copy and fail if different
  if [ "$CHECK_LOCK" = true ]; then
    if [ -f "$PYLOCK" ]; then
      local TMP_PL
      TMP_PL="$(mktemp -t pylock.XXXXXX)" || { echo "mktemp failed"; return 1; }
      UV_TORCH_BACKEND="$SELECTED_TORCH_BACKEND" "$UV_BIN" pip compile requirements.txt --format pylock.toml -o "$TMP_PL" || { echo "uv pip compile failed for check-lock"; rm -f "$TMP_PL"; return 1; }
      if ! diff -u "$PYLOCK" "$TMP_PL" >/dev/null 2>&1; then
        echo "pylock.toml in repo differs from freshly compiled lock (backend: $SELECTED_TORCH_BACKEND)."
        echo "Run 'install_uv --update-lock' to regenerate pylock.toml and commit the change, or review differences below:"
        diff -u "$PYLOCK" "$TMP_PL" || true
        rm -f "$TMP_PL"
        return 2
      fi
      rm -f "$TMP_PL"
      echo "pylock.toml is up-to-date with the compiled lock (backend: $SELECTED_TORCH_BACKEND)."
    else
      echo "No pylock.toml found to check against; run --update-lock to generate one.";
      return 3
    fi
  fi

  # Decide torch backend if not explicitly provided
  # Ensure sync uses the same backend as the compile step unless the user explicitly
  # provided --torch-backend. SELECTED_TORCH_BACKEND was used for compile; default
  # the sync backend to that to avoid mismatches.
  if [ -z "$TORCH_BACKEND" ]; then
    TORCH_BACKEND="$SELECTED_TORCH_BACKEND"
  fi
  printf 'Compile-time selected backend: %s\n' "$SELECTED_TORCH_BACKEND"
  printf 'Sync-time backend to be used: %s\n' "$TORCH_BACKEND"

  # Sync packages into the venv (with optional dry-run preview)
  echo "Syncing packages into venv with uv pip sync..."
  local SYNC_TARGET=""
  if [ -f "$LOCKFILE" ]; then
    SYNC_TARGET="$LOCKFILE"
  elif [ -f "$PYLOCK" ]; then
    SYNC_TARGET="$PYLOCK"
  fi

  # If dry-run requested, attempt to preview the plan. If uv doesn't support
  # --dry-run the command may fail; offer the user a choice to continue.
  if [ "$DRY_RUN" = true ]; then
    if [ -n "$SYNC_TARGET" ]; then
      echo "Running dry-run preview (uv pip sync --dry-run) against: $SYNC_TARGET"
      if "$UV_BIN" pip sync "$SYNC_TARGET" --python "$VENV_PYTHON" --torch-backend "$TORCH_BACKEND" --dry-run; then
        if [ "$AUTO_YES" = true ] || [ "$APPLY" = true ]; then
          echo "Auto-confirm enabled; proceeding with actual installation"
        else
          read -rp "Proceed with actual installation? [y/N]: " _resp
          if ! printf '%s' "${_resp:-N}" | grep -Eq '^[Yy]'; then
            echo "Aborting per user request"
            return 0
          fi
        fi
      else
        if [ "$AUTO_YES" = true ] || [ "$APPLY" = true ]; then
          echo "Dry-run not supported or failed; AUTO_YES/APPLY set - continuing with installation"
        else
          echo "Dry-run preview failed or --dry-run unsupported. Continue with install? [y/N]"
          read -rp "" _resp
          if ! printf '%s' "${_resp:-N}" | grep -Eq '^[Yy]'; then
            echo "Aborting per user request"
            return 1
          fi
        fi
      fi
    else
      echo "No lockfile (uv.lock/pylock.toml) found; cannot perform a dry-run preview for pip install -r requirements.txt"
      if [ "$AUTO_YES" = true ] || [ "$APPLY" = true ]; then
        echo "AUTO_YES/APPLY set - proceeding with pip install -r requirements.txt"
      else
        read -rp "Proceed with pip install -r requirements.txt? [y/N]: " _resp
        if ! printf '%s' "${_resp:-N}" | grep -Eq '^[Yy]'; then
          echo "Aborting per user request"
          return 1
        fi
      fi
    fi
  fi

  if [ -n "$SYNC_TARGET" ]; then
    "$UV_BIN" pip sync "$SYNC_TARGET" --python "$VENV_PYTHON" --torch-backend "$TORCH_BACKEND" || { echo "uv pip sync failed"; return 1; }
  else
    echo "No lockfile found, falling back to pip install -r requirements.txt"
    "$VENV_PYTHON" -m pip install -r requirements.txt || { echo "pip install failed"; return 1; }
  fi

  # After syncing, ensure pip is available in the venv: some sync operations
  # may remove or replace pip. If pip is missing, try to bootstrap it via
  # ensurepip first, then fall back to get-pip.py. Avoid force-upgrading
  # setuptools here to prevent conflicts with packages like torch which may
  # require an upper-bound on setuptools.
  if ! "$VENV_PYTHON" -m pip --version >/dev/null 2>&1; then
    echo "pip not found in venv after uv pip sync; attempting to bootstrap via ensurepip..."
    if "$VENV_PYTHON" -m ensurepip --upgrade >/dev/null 2>&1; then
      echo "ensurepip succeeded"
    else
      echo "ensurepip failed; attempting to download get-pip.py as fallback"
      local TMP_GET_PIP
      TMP_GET_PIP="$(mktemp -t get-pip.XXXXXX)" || { echo "mktemp failed"; return 1; }
      if command -v curl >/dev/null 2>&1; then
        curl -sS https://bootstrap.pypa.io/get-pip.py -o "$TMP_GET_PIP" || { echo "curl failed"; rm -f "$TMP_GET_PIP"; return 1; }
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP_GET_PIP" https://bootstrap.pypa.io/get-pip.py || { echo "wget failed"; rm -f "$TMP_GET_PIP"; return 1; }
      else
        echo "ERROR: cannot download get-pip.py because neither curl nor wget is available"
        rm -f "$TMP_GET_PIP"
        return 1
      fi
      # Install pip but avoid touching setuptools if possible; get-pip.py may
      # upgrade setuptools - in that case, the user should prefer running
      # install_uv with --update-lock to align lockfile.
      "$VENV_PYTHON" "$TMP_GET_PIP" || { echo "get-pip.py failed"; rm -f "$TMP_GET_PIP"; return 1; }
      rm -f "$TMP_GET_PIP"
    fi
  fi

  # Post-sync compatibility check: ensure installed setuptools satisfies
  # any setuptools requirement declared by installed torch (if present).
  echo "Checking setuptools compatibility with installed torch (if any)..."
  if ! "$VENV_PYTHON" - <<'PY'
import sys, re
from importlib import metadata as md
try:
    torch_ver = md.version('torch')
except Exception:
    # torch not installed; nothing to check
    sys.exit(0)
try:
    setuptools_ver = md.version('setuptools')
except Exception:
    print('ERROR: setuptools is not installed in the venv', file=sys.stderr)
    sys.exit(1)
reqs = []
try:
    meta = md.metadata('torch')
    # metadata.get_all may return None or a sequence
    reqs = meta.get_all('Requires-Dist') or []
except Exception:
    reqs = []

# Try to parse setuptools requirement robustly. Prefer packaging.Requirement when available.
try:
    from packaging.requirements import Requirement as _Req
    from packaging.specifiers import SpecifierSet as _SpecSet
    from packaging.version import Version as _Version
    _packaging_available = True
except Exception:
    _packaging_available = False

# Look through Requires-Dist entries for any setuptools requirement
found_setuptools_req = False
for r in reqs:
    if 'setuptools' not in r.lower():
        continue
    # packaging-based parsing if available
    if _packaging_available:
        try:
            reqobj = _Req(r)
            if reqobj.name.lower() != 'setuptools':
                continue
            found_setuptools_req = True
            spec = str(reqobj.specifier)
            if not spec:
                # no version constraint; nothing to enforce
                continue
            s = _SpecSet(spec)
            sv = _Version(setuptools_ver)
            if sv not in s:
                print(f"ERROR: setuptools {setuptools_ver} does not satisfy torch requirement: {spec}", file=sys.stderr)
                sys.exit(1)
            continue
        except Exception:
            # fall back to legacy parsing below
            pass

    # Legacy parsing: accept forms like 'setuptools (<82)' or 'setuptools <82,>=40'
    m = re.search(r'setuptools\s*\(([^)]+)\)', r, flags=re.IGNORECASE)
    if m:
        spec = m.group(1).strip()
    else:
        m2 = re.search(r'setuptools\s*([<>=!~,\s\d\.]+)', r, flags=re.IGNORECASE)
        if m2:
            spec = m2.group(1).strip()
        else:
            # no specifier found; treat as no constraint
            continue

    # simple numeric check fallback: compare numeric version tuples for common operators
    tokens = [t.strip() for t in spec.split(',') if t.strip()]
    def vtuple(v):
        nums = re.findall(r'\d+', v)
        return tuple(int(x) for x in nums) if nums else (0,)
    svt = vtuple(setuptools_ver)
    ok = True
    for t in tokens:
        t_norm = t.replace(' ', '')
        if t_norm.startswith('<='):
            n = vtuple(t_norm[2:])
            if not svt <= n: ok = False
        elif t_norm.startswith('<'):
            n = vtuple(t_norm[1:])
            if not svt < n: ok = False
        elif t_norm.startswith('>='):
            n = vtuple(t_norm[2:])
            if not svt >= n: ok = False
        elif t_norm.startswith('>'):
            n = vtuple(t_norm[1:])
            if not svt > n: ok = False
        elif t_norm.startswith('=='):
            n = vtuple(t_norm[2:])
            if not svt == n: ok = False
    if not ok:
        print(f"ERROR: setuptools {setuptools_ver} does not satisfy torch requirement: {spec}", file=sys.stderr)
        sys.exit(1)
    found_setuptools_req = True

if not found_setuptools_req:
    # no explicit setuptools requirement; nothing to enforce
    sys.exit(0)

sys.exit(0)
PY
  then
    echo "Setuptools compatibility check failed; please run install_uv --update-lock or adjust your environment.";
    return 1
  else
    echo "Setuptools compatibility OK"
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
     install_uv --install-shell-func    # writes helper to ~/.local/etc/bash.d and prints a one-time
                                       # snippet to enable it in your shell rc; it does NOT edit your rc

5) See full installer help:
     install_uv --help

GUIDE
fi

# Print installer id to help debugging which copy/version was sourced
printf 'installer id: %s\n' "${INSTALLER_ID-$(date -u +%Y%m%dT%H%M%SZ)}"

# End of file - functions are defined when this file is sourced.
