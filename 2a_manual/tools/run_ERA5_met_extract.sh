#!/bin/bash -l

# These qsub options tailored for BU's SCC cluster
# Will need translation for slurm-based systems
#$ -pe omp 28
#$ -l mem_per_core=4G
#$ -o prep_getERA5_met.log
#$ -j y

module load R

echo "starting at" $(date)
time Rscript tools/prep_getERA5_met.R
echo "done at" $(date)
