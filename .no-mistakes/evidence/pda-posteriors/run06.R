ns <- asNamespace("PEcAn.settings")
utils::assignInNamespace("set_site_paths", function(settings, input_type, ...) {
  s <- settings$run$site
  paths <- PEcAn.settings:::build_pathset(id = s$id, WRF_grid_cell = s$WRF_grid_cell %||% s$id, ...)
  settings$run$inputs[[input_type]]$path <- paths
  settings
}, ns = "PEcAn.settings")
`%||%` <- function(a, b) if (is.null(a)) b else a
source(Sys.getenv("SCRIPT"))
