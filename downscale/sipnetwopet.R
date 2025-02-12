#' SIPNETWOPET, the "Simpler Photosynthesis and EvapoTranspiration model,
#' WithOut Photosynthesis and EvapoTranspiration"
#'
#' This function simulates soil organic carbon (SOC) and aboveground
#' biomass (AGB) using the SIPNETWOPET model. It is a surrogate for
#' SIPNET, a process-based model that simulates the carbon and water.
#' It can generate ensemble predictions for SOC and AGB and has its own
#' internal stochastic model. SIPNETWOPET promises rough
#' relationships between environmental variables and SOC and AGB.
#'
#' @param temp Mean annual temperature (degrees Celsius)
#' @param precip Mean annual precipitation (mm)
#' @param clay Clay content (%)
#' @param ocd Organic carbon density (g/cm^3)
#' @param twi Topographic wetness index
#' @param ensemble_size Number of ensemble predictions to generate (default 10)
#'
#' @return A tibble with columns \code{ensemble_id}, \code{soc}, and \code{agb}
#' for each ensemble member. Unspecified units.
#'
#' @author David LeBauer
#'
#' @examples
#' @examples
#' sipnetwopet(temp = 22, precip = 4500, clay = 25, ocd = 0.3, twi = 9, ensemble_size = 5)
#'
sipnetwopet <- function(
    temp, precip, clay, ocd, twi, ensemble_size = 10) {
    ensemble_results <- list()
    for (i in seq_len(ensemble_size)) {
        # Manually scale inputs using predefined dataset statistics
        scaled_temp <- (temp - 20) / 2
        scaled_precip <- (precip - 5000) / 2000
        scaled_clay <- (clay - 20) / 6
        scaled_ocd <- (ocd - 300) / 60
        scaled_twi <- (twi - 10) / 2

        # Add stochastic variation
        scaled_temp <- scaled_temp * rnorm(1, 1, 0.1)
        scaled_precip <- scaled_precip * rnorm(1, 1, 0.1)
        scaled_clay <- scaled_clay * rnorm(1, 1, 0.1)
        scaled_ocd <- scaled_ocd * rnorm(1, 1, 0.1)
        scaled_twi <- scaled_twi * rnorm(1, 1, 0.1)

        # Simulate SOC with environmental effects and bounds
        .soc <- 80 + 15 * scaled_precip + 12 * scaled_temp + 50 * scaled_ocd + 15 * scaled_clay + 8 * scaled_twi +
            rnorm(1, 0, 10)
        soc <- max(90 * (.soc / (100 + abs(.soc))), rlnorm(1, meanlog = log(50), sdlog = 0.3))

        # Simulate AGB with environmental effects and bounds
        .agb <- 120 + 25 * scaled_temp + 35 * scaled_precip + 10 * scaled_clay -
            8 * scaled_twi + rnorm(1, 0, 15)
        agb <- max(450 * (.agb / (500 + abs(.agb))), rlnorm(1, meanlog = log(20), sdlog = 0.4))

        ensemble_results[[i]] <- tibble::tibble(soc = soc, agb = agb)
    }

    ensemble_data <- dplyr::bind_rows(ensemble_results, .id = "ensemble_id")
    return(ensemble_data)
}
