#!/bin/bash

set -e

SIPNET_DIR=${1:-~/sipnet}
BIN_DIR=${2:-~/sipnet_binaries}
LINK_DEST=${3:-./sipnet.git}

# I think git and gcc are available by default here
# If not true on other sytems, might need e.g `module load gcc`
mkdir -p "$BIN_DIR"
BIN_DIR=$(realpath "$BIN_DIR")

git clone https://github.com/PecanProject/sipnet.git "$SIPNET_DIR"
cd "$SIPNET_DIR" \
	&& GIT_REV=$(git rev-parse --short HEAD) \
	&& srun -n1 make sipnet \
	&& mv sipnet "$BIN_DIR"/sipnet_"$GIT_REV" \
	&& cd -

cd $(dirname $(realpath "$LINK_DEST"))
ln -s "$BIN_DIR"/sipnet_"$GIT_REV" $(basename "$LINK_DEST")
