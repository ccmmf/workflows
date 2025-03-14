
Put inputs where they're expected:
```{sh}
# curl -o cccmmf_phase_1b_input_artifacts.tgz [url TK] 
tar xzf cccmmf_phase_1b_input_artifacts.tgz
# ln -s $(which sipnet.git) sipnet.git
```

And run
(Adjust all slurm flags to your machine, of course)
(No, it did not in fact take ten hours to run; log timestamps say it took about half an hour wall time)

```{sh}
module load r
sbatch -n1 --cpus-per-task=4 ./tools/ERA5_nc_to_clim.R
srun ./ic_build.R
srun ./xml_build.R
sbatch --mem-per-cpu=1G --time=10:00:00 \
  --output=ccmmf_phase_1b_"$(date +%Y%m%d%H%M%S)_%j.log" \
  ./run_model.R -s settings.xml
```

tar up outputs + run log + selected inputs for archiving / analysis
(Note this doesn't currently include the weather files)

```
# assumes the log I care about is the newest one as sorted by -t...
runlog=$(ls -1t ccmmf_phase_1b*.log | head -n1)
tarname=${runlog/log/tgz}
srun --mem-per-cpu=5G --time=5:00:00 \
	tar czf "$tarname" \
	"$runlog" settings.xml site_info.csv \
	output IC_files data/IC_prep
```
