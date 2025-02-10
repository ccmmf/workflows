#!/bin/bash

#SBATCH --cpus-per-task=1 --time=00:05:00 --output=install.sh.out

set -e

BIN_DIR=${1:-"~/sipnet_binaries"}
LINK_DEST=${2:-"./sipnet.git"}

# I think git and gcc are available by default here
# If not true on other sytems, might need e.g `module load gcc`
mkdir -p "$BIN_DIR"
BIN_DIR=$(realpath "$BIN_DIR")

git clone https://github.com/PecanProject/sipnet.git
cd sipnet
GIT_REV=$(git rev-parse --short)
make sipnet
mv sipnet "$BIN_DIR"/sipnet_"$GIT_REV"

cd $(dirname $(realpath "$LINK_DEST"))
ln -s "$BIN_DIR"/sipnet_"$GIT_REV" $(basename "$LINK_DEST")
