
allom_kgC_m2 <- function(age, species = c("almond", "walnut", "pistachio", "orange")) {
  if (any(age > 50)) stop("this allometry only valid to age 50")
  species <- match.arg(species)

  dens_m <- c(almond = -15.45, walnut = -19.97, pistachio = -24.7, orange = -34.71)
  dens_b <- c(almond = 125.72, walnut = 103.5, pistachio = 184.93, orange = 223.83)
  carbon_m <- c(almond = 12.9823, walnut = 9.3295, pistachio = 1.2879, orange = 2.4435)
  carbon_b <- c(almond = 1.3923, walnut = 1.6121, pistachio = 1.8835, orange = 1.3712)

  trees_acre <- dens_m[species] * log(age) + dens_b[species]
  lbs_tree <- carbon_m[species] * (age^carbon_b[species])

  PEcAn.utils::ud_convert(trees_acre * lbs_tree, "lb acre-1", "kg m-2")
}
