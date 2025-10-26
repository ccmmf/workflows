#!/bin/bash

#SBATCH -n1
#SBATCH --time=00:10:00

# Compiles Sipnet with support for management events,
# adds revision hash to the binary name,
# and creates a symlink to it in your workdir or bindir of choice.

# Usage:
#  install_sipnet.sh path/to/repo/ path/to/bin/ path/to/symlinked/sipnet
# All paths will be created if needed; link will be overwritten if extant

set -e

SIPNET_DIR=${1:-~/sipnet}
BIN_DIR=${2:-~/sipnet_binaries}
LINK_DEST=${3:-./sipnet.git}

# I think git and gcc are available by default here
# If not true on other sytems, might need e.g `module load gcc`
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
ln -s "$BIN_DIR"/sipnet_"$GIT_REV" $(basename "$LINK_DEST")
