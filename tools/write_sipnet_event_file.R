#!/usr/bin/env Rscript

# Write a Sipnet `events.in` file that declares 2.8 cm of irrigation every
# four days from April through October of each year,
# for about 1500 mm of water added.

# TODO 1: account for site and time variation; eventually will want to work
# from sensed water status

# TODO 2: update run.write.configs to create sipnet.event for us


fixed_amount_irrigation <- function(year, cm_added,
                                    doy_start, doy_end, day_interval,
                                    type = c("canopy", "soil", "flood")) {
  type <- match.arg(type)
  type_num <- c(canopy = 0, soil = 1, flood = 2)[type]

  irrig_days <- seq(from = doy_start, to = doy_end, by = day_interval)
  cm_per_event <- round(cm_added / length(irrig_days), digits = 1)

  data.frame(
    year = year,
    yday = irrig_days,
    event = "irrig",
    amount = cm_per_event,
    type = type_num
  )
}

purrr::map(
  2016:2023,
  ~ fixed_amount_irrigation(
    year = .,
    cm_added = 150,
    doy_start = 92,
    doy_end = 305,
    day_interval = 4,
    type = "soil"
  )
) |>
  purrr::list_rbind() |>
  write.table("events.in", row.names = FALSE, col.names = FALSE, quote = FALSE)
