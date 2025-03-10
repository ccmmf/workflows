
Put inputs where they're expected:
```{sh}
# curl -o cccmmf_phase_1b_input_artifacts.tgz [url TK] 
tar xz cccmmf_phase_1b_input_artifacts.tgz
# ln -s $(which sipnet.git) sipnet.git
```

And run
```{sh}
module load r
sbatch -n1 --cpus-per-task=8 ./tools/ERA5_met_to_clim.R
./xml_build.R
./ic_build.R
./run_models.R -s settings.xml
```
