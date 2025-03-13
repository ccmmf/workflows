#!/bin/bash

launchdir=$(dirname "$1")
logfile="$launchdir"/slurm_submit_log.txt
joblistfile="$launchdir"/joblist.txt

if [[ -z ${SLURM_ARRAY_TASK_ID} ]]; then
	echo "SLURM_ARRAY_TASK_ID not set. Exiting." >> "$logfile"
	exit 1
fi

# joblist.txt has job script name on line 1, invocation dirs on lines 2-n
# => add 1 to each task ID to get its line number
task_line=$((SLURM_ARRAY_TASK_ID + 1))
if [[ "$task_line" -gt "$(wc -l < "$joblistfile")" ]]; then
	# TODO do we want to warn here? For now assuming no,
	# to allow arrays with empty slots
	exit 0
fi

jobscript=$(head -n1 "$joblistfile")
taskdir=$(tail -n+"$task_line" "$joblistfile" | head -n1)

"$taskdir"/"$jobscript" >> "$logfile" 2>&1

if [[ "$?" != "0" ]]; then
	echo "ERROR IN MODEL RUN" >> "$logfile"
	echo "Errored with: task ID $SLURM_ARRAY_TASK_ID, in dir $taskdir" >> "$logfile"
	exit 1
fi
