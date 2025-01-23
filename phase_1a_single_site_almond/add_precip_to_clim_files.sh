# Creating Sipnet inputs with extra precipitation to approximate irrigation
#
# Here I add 0.43 mm of pseudo-precip to every line of each climate file.
# Since one line is a 3-hr interval this is approximately equal to the
# 1259 mm/yr average irrigation reported by Khalsa et al 2020.
#
# There's nothing biologically realistic about the every-3-hr part,
#  it's just very easy to do with awk.
#
# We have already started implementing support for more realistic irrigation
# events in SipNet itself, so these files are a short-term hack.

mkdir ERA5_losthills_dailyrain
cd ERA5_losthills_SIPNET

# awk is powerful and compact, but its commands are some real gobbledygook!
# Breaking it down:
#  * `OFS="\t"` sets output as tab-separated
#  * `$9 = $9 + 0.43` adds 0.43 to the numeric value of field 9 on every line
#  * `print $0` prints the whole modified line
#  * `>>(somefile)` sends result to somefile
#     (but for me it still echoes all lines to the console too --
#      not sure if this can be changed)
#  * `FILENAME` is replaced with name of input file
awk 'OFS="\t";{$9 = $9 + 0.43; print $0 >("../ERA5_losthills_dailyrain/"FILENAME)}' *.clim
