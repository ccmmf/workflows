#!/bin/bash

# Installs PEcAn, Sipnet, and the prebuilt input files needed for a statewide woody crop simulation.

# ------Edit this section as needed for your system--------

#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=1G
#SBATCH --time="12:00:00"
#SBATCH --output=00_install.out

# Locations to use for Sipnet installation.
# All are created for you if they don't exist.
SIPNET_SRC_DIR=~/sipnet/
SIPNET_BIN_ARCHIVE=~/sipnet_binaries/
SIPNET_EXE_LINK=./sipnet.git

# Where to retrieve zip file of prebuilt inputs
ARTIFACT_LINK='https://drive.usercontent.google.com/download?id=15DVcJy-faUfLThon7ScqMwAsy_fxuLe_&export=download&confirm=t'
ARTIFACT_NAME='cccmmf_phase_1b_input_artifacts.tgz'

# --- end setup --------------------------------------------
set -e

./tools/install_sipnet.sh "$SIPNET_SRC_DIR" "$SIPNET_BIN_ARCHIVE" "$SIPNET_EXE_LINK"

./tools/install_pecan.sh

curl -L -o "$ARTIFACT_NAME" "$ARTIFACT_LINK" \
	&& tar xf "$ARTIFACT_NAME"
