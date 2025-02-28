#!/bin/bash -l

# These qsub options tailored for BU's SCC cluster
# Will need translation for slurm-based systems
#$ -pe omp 8
#$ -o prep_getERA5_met.log
#$ -j y

module load R

echo "starting at" $(date)
time ./prep_getERA5_met.R
echo "done at" $(date)
