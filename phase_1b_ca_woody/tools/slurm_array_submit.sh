#!/bin/bash

launchdir=$(dirname "$1")
logfile="$launchdir"/slurm_submit_log.txt

if [[ -z ${SLURM_ARRAY_TASK_ID} ]]; then
	echo "SLURM_ARRAY_TASK_ID not set. Exiting." >> "$logfile"
	exit 1
fi

# joblist.txt has job script name on line 1, invocation dirs on lines 2-n
# => add 1 to each task ID to get its line number
jobscript=$(head -n1 "$launchdir"/joblist.txt)
task_line=$((SLURM_ARRAY_TASK_ID + 1))
taskdir=`tail -n+"$task_line" "$launchdir"/joblist.txt | head -n1`

"$taskdir"/"$jobscript" >> "$logfile" 2>&1

if [[ "$?" != "0" ]]; then
	echo "ERROR IN MODEL RUN" >> "$logfile"
	exit 1
fi
