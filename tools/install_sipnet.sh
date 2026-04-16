#!/usr/bin/env bash
# install_sipnet.sh: Clone, compile, and symlink SIPNET.
#
# Usage: install_sipnet.sh <sipnet_src_dir> <sipnet_bin_dir> <symlink_dest> [<revision>]
#
#   sipnet_src_dir  Directory into which to clone the SIPNET repo (created if absent).
#   sipnet_bin_dir  Directory in which to store compiled binaries (created if absent).
#   symlink_dest    Path at which to create/update a symlink to the compiled binary.
#   revision        Optional git commit SHA or tag to build. Defaults to HEAD.
#
# Idempotent: skips clone if src_dir already exists; skips compile if the
# versioned binary (sipnet_<git-rev>) is already present in bin_dir.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: install_sipnet.sh <sipnet_src_dir> <sipnet_bin_dir> <symlink_dest> [<revision>]" >&2
  exit 1
fi

SIPNET_SRC="$1"
BIN_DIR="$2"
LINK_DEST="$3"
REVISION="${4:-}"

# --- Clone ---
if [[ ! -d "$SIPNET_SRC" ]]; then
  echo "install_sipnet: cloning SIPNET into $SIPNET_SRC"
  git clone https://github.com/PecanProject/sipnet.git "$SIPNET_SRC"
else
  echo "install_sipnet: SIPNET source already present at $SIPNET_SRC"
fi

# --- Resolve revision and determine versioned binary name ---
GIT_REV=$(
  cd "$SIPNET_SRC"
  git fetch --quiet
  if [[ -n "$REVISION" ]]; then
    git checkout --quiet "$REVISION"
  fi
  git rev-parse --short HEAD
)

mkdir -p "$BIN_DIR"
BIN_DIR=$(realpath "$BIN_DIR")
BINARY="${BIN_DIR}/sipnet_${GIT_REV}"

# --- Compile ---
if [[ ! -f "$BINARY" ]]; then
  echo "install_sipnet: compiling SIPNET revision $GIT_REV"
  (cd "$SIPNET_SRC" && make sipnet)
  mv "${SIPNET_SRC}/sipnet" "$BINARY"
  echo "install_sipnet: binary stored at $BINARY"
else
  echo "install_sipnet: binary already compiled at $BINARY"
fi

# --- Symlink ---
LINK_DIR=$(dirname "$(realpath -m "$LINK_DEST")")
LINK_NAME=$(basename "$LINK_DEST")
mkdir -p "$LINK_DIR"
ln -sf "$BINARY" "${LINK_DIR}/${LINK_NAME}"
echo "install_sipnet: symlink ${LINK_DIR}/${LINK_NAME} -> $BINARY"
