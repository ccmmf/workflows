#!/bin/bash

#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=4
#SBATCH --tasks=1

# Collects the output directory into a compressed tarball,
# adding validation output and run logs if present
#
# TODO We may want to include at least some inputs too
# (but I don't _think_ we want the entire working directory).
# Add these as we find we want them.

TFMT='+%Y%m%d_%H%M%S%Z'
TS=$(date "$TFMT")
OUTFILE=${1:-ccmmf_output_"$TS".tgz}

# Copy validation notebook and run logs into the output,
# adding modifitation timestamps to avoid clobbering previous files.
# TODO are the timestamps more confusing than helpful?
if [[ -f 05_validation.html ]]; then
	VAL_TS=$(date -r 05_validation.html "$TFMT")
	cp -v 05_validation.html output/05_validation_"$VAL_TS".html
fi
for l in $(find . -name '*.log' -depth 1); do
	LOG_TS=$(date -r "$l" "$TFMT")
	cp -v "$l" output/"${l//.}"_"$LOG_TS".log 
done

echo "output/ -> $OUTFILE"
tar czf "$OUTFILE" output/
