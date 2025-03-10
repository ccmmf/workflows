
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
srun ./xml_build.R
srun ./ic_build.R
sbatch --mem-per-cpu=1G --time=01:00:00 \
  --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" \
  ./run_model.R -s settings.xml
```
