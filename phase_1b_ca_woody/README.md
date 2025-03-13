
Put inputs where they're expected:
```{sh}
# curl -o cccmmf_phase_1b_input_artifacts.tgz [url TK] 
tar xz cccmmf_phase_1b_input_artifacts.tgz
# ln -s $(which sipnet.git) sipnet.git
```

And run
(Adjust all slurm flags to your machine, of course)
```{sh}
module load r
sbatch -n1 --cpus-per-task=4 ./tools/ERA5_nc_to_clim.R
srun ./ic_build.R
srun ./xml_build.R
sbatch --mem-per-cpu=1G --time=10:00:00 \
  --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%A-%a.log" \
  ./run_model.R -s settings.xml
```

tar up outputs + run log for archiving / analysis
```
# assumes the log I care about is the one that sorts last...
cp $(ls -1 pecan_workflow_runlog* | tail -n1) output/
srun --mem-per-cpu=5G --time=5:00:00 \
	tar czf ccmmf_phase_1b_98sites_20reps_20250312.tgz output
```

Later I wanted more diagnostics about IC files -- consider packaging these with outputs in the first place
```
tar czf ccmmf_20250312_ic_diagnostics.tgz IC_files/ data/IC_prep/ site_info.csv settings.xml pfts/
```