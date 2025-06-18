#!/bin/bash

if [[ $# -lt 2 ]]; then
	echo "Copies a folder full of clim files and modifies them" \
		" by adding 0.43 mm of rain to every line"
	echo "Usage: 02_prep_add_precip_to_clim_files.sh path/to/sourcedir/ path/to/outdir/"
	exit 0
fi

# Creating Sipnet inputs with extra precipitation to approximate irrigation
#
# Here I add 0.43 mm of pseudo-precip to every line of each climate file.
# Since one line is a 3-hr interval this is approximately equal to the
# 1259 mm/yr average irrigation reported by Khalsa et al 2020.
#
# There's nothing biologically realistic about the every-3-hr part,
#  it's just very easy to do with awk.
#
# We have already started implementing support for more realistic irrigation
# events in SipNet itself, so these files are a short-term hack.

SRC_PATH=$(realpath ${1:-'data/ERA5_losthills_SIPNET'})
DEST_PATH=${2:-'data/ERA5_losthills_dailyrain'}
if [[ ! -d "$DEST_PATH" ]]; then
	mkdir -p "$DEST_PATH"
fi
DEST_PATH=$(realpath "$DEST_PATH")

cd "$SRC_PATH"

# awk is powerful and compact, but its commands are some real gobbledygook!
# Breaking it down:
#  * `OFS="\t"` sets output as tab-separated
#  * `$9 = $9 + 0.43` adds 0.43 to the numeric value of field 9 on every line
#  * `print $0` prints the whole modified line
#  * `>>(somefile)` sends result to somefile
#     (but for me it still echoes all lines to the console too --
#      not sure if this can be changed)
#  * `FILENAME` is replaced with name of input file
awk 'OFS="\t";{$9 = $9 + 0.43; print $0 >("'"$DEST_PATH"'/"FILENAME)}' *.clim
