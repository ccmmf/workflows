#!/bin/bash
# Runs the real SIPNET binary for Jan-Mar 2016 (before any planting event)
# (/usr/local/bin/sipnet.git, the binary workflow/template.xml points at)
# with the sipnet.param that write.config.SIPNET produced from the base and
# the fixed annual IC member 1, using a synthetic daily winter climate.
#
# usage: run_sipnet_annual.sh <scratch_dir> <evidence_dir>
set -euo pipefail
S=$1; EV=$2
for v in base fixed; do
  d=$S/sipnet_run/$v
  rm -rf "$d"; mkdir -p "$d"
  cp "$S/configs/$v/run/annual/"{sipnet.in,sipnet.param,sipnet.param-spatial} "$d/"
  # loc year doy hour dt(days) Tair Tsoil PAR(mol/m2/step) precip(mm/step) VPD vpdSoil vPress wspd soilWetness
  awk 'BEGIN { for (d = 1; d <= 91; d++) printf "0 2016 %d 0.00 1.0000 10.0 9.0 20.0 2.0 500 300 1000 2.0 0.6\n", d }' > "$d/sipnet.clim"
  (cd "$d" && /usr/local/bin/sipnet.git -i sipnet.in > sipnet.log 2>&1) || { echo "sipnet failed for $v"; cat "$d/sipnet.log"; exit 1; }
done
Rscript - "$S/sipnet_run" "$EV" <<'EOF'
a <- commandArgs(trailingOnly = TRUE)
rd <- function(v) {
  x <- read.table(file.path(a[1], v, "sipnet.out"), header = TRUE, skip = 1, comment.char = "")
  x$version <- v
  x
}
o <- rbind(rd("base"), rd("fixed"))
write.csv(o, file.path(a[2], "sipnet_annual_JanMar_daily.csv"), row.names = FALSE)
cols <- intersect(c("version", "year", "day", "time", "plantLeafC", "gpp", "npp", "nee"), names(o))
cat("SIPNET output columns:", paste(names(o), collapse = " "), "\n\n")
cat("== First 5 days of each run ==\n")
print(do.call(rbind, lapply(split(o, o$version), head, 5))[, cols], row.names = FALSE)
cat("\n== Jan 1 - Mar 31 2016 totals, annual site IC member 1 (no planting events) ==\n")
s <- do.call(rbind, lapply(split(o, o$version), function(x) data.frame(
  version = x$version[1],
  leafC_day1 = x$plantLeafC[1],
  leafC_max = max(x$plantLeafC),
  gpp_total = sum(x$gpp),
  days_with_gpp = sum(x$gpp > 0)
)))
print(s, row.names = FALSE)
EOF
