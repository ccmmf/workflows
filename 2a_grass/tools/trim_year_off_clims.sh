#!/bin/bash

# I have a whole bunch of Sipnet clim files that supposedly contain data for
# 2024, but it is all NA. This confuses Sipnet (and, weirdly, makes it eat all
# available memory: https://github.com/PecanProject/pecan/issues/2156).

# To use these files until the source of the NAs is debugged and fixed,
# I'll remove the NA lines and end the simulation in 2023.

# wanted to use existing folder name for output, so I renamed input first:
# mv data/ERA5_SIPNET data/ERA5_SIPNET_2016_2024

indir="data/ERA5_SIPNET_2016_2024"
outdir="data/ERA5_SIPNET"


# Checking first: Are all missing values from 2024?
# $ grep -ch 'NA' -R "$indir"/**/*.clim | sort -n | uniq 
# 2928
# $ grep -ch '2024.*NA' -R "$indir"/**/*.clim | sort -n | uniq 
# 2928
# ==> yes, they are

for sitein  in "$indir"/*; do
	siteout=${sitein//"$indir"/"$outdir"}
	mkdir -p "$siteout"
	for i in {1..10}; do
		sed '/NA/d' "$sitein"/ERA5."$i".2016-01-01.2024-12-31.clim \
			> "$siteout"/ERA5."$i".2016-01-01.2023-12-31.clim
	done
done
