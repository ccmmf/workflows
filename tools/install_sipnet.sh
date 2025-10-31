#!/bin/bash

#SBATCH -n1
#SBATCH --time=00:10:00

# Compiles the latest version of Sipnet,
# adds revision hash to the binary name,
# and creates a symlink to it in your workdir or bindir of choice.
#
# The script will:
# - Clone the repo if it doesn't exist, or update it via git pull
# - Fail if the repo contains uncommitted changes
# - Run 'make clean' and 'make' to build a fresh binary
# - Move the binary to BIN_DIR with git hash appended to filename
# - Create/overwrite a symlink at LINK_DEST pointing to the binary

# Usage:
# install_sipnet.sh [path/to/repo/] [path/to/bin/] [path/to/symlinked/sipnet]
#
# Arguments (all optional, with defaults):
# - SIPNET_DIR  - directory for sipnet repository (default: ~/sipnet)
# - BIN_DIR     - directory for versioned binaries (default: ~/sipnet_binaries)
# - LINK_DEST   - path where symlink will be created (default: ./sipnet.git)
#
# All paths will be created if needed; link will be overwritten if it exists

set -e

SIPNET_DIR=${1:-~/sipnet}
BIN_DIR=${2:-~/sipnet_binaries}
LINK_DEST=${3:-./sipnet.git}

# I think git and gcc are available by default here
# If not true on other systems, might need e.g `module load gcc`
mkdir -p "$BIN_DIR"
BIN_DIR=$(realpath "$BIN_DIR")

if [[ -d "$SIPNET_DIR" ]]; then
	if [[ ! -z $(git -C "$SIPNET_DIR" status -s) ]]; then
		echo "Sipnet repo contains uncommited changes, so not updating."
		echo "Please commit or stash your work before rerunning."
		exit 1
	fi
	cd "$SIPNET_DIR" && git checkout master && git pull && cd -
else
	git clone https://github.com/PecanProject/sipnet.git "$SIPNET_DIR"
fi

cd "$SIPNET_DIR" \
	&& GIT_REV=$(git rev-parse --short HEAD) \
  && make clean \
	&& make \
	&& mv sipnet "$BIN_DIR"/sipnet_"$GIT_REV" \
	&& cd -

cd $(dirname $(realpath "$LINK_DEST"))
ln -sf "$BIN_DIR"/sipnet_"$GIT_REV" $(basename "$LINK_DEST")
