#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import shiny
#' @import R6
#' @importFrom cli cli_abort cli_inform cli_warn
#' @importFrom checkmate assert_character assert_integerish assert_data_frame
#' @importFrom DBI dbConnect dbReadTable dbExecute
#' @importFrom duckdb duckdb
#' @importFrom htmlwidgets createWidget shinyWidgetOutput shinyRenderWidget
#' @importFrom rlang "%||%"
## usethis namespace: end
NULL

#' Initialize package on load
#'
#' @keywords internal
#' @noRd
.onLoad <- function(libname, pkgname) {
  # Initialize DuckDB schema (idempotent)
  tryCatch({
    db_config <- get_golem_config("database")
    db_path <- system.file("extdata", db_config$name, package = pkgname)
    
    if (file.exists(db_path)) {
      con <- DBI::dbConnect(duckdb::duckdb(), db_path)
      source(system.file("app/db_init.R", package = pkgname), local = TRUE)
      initialize_duckdb_schema(con)
      DBI::dbDisconnect(con, shutdown = TRUE)
    }
  }, error = function(e) {
    # Non-critical: silently skip if schema init fails
    # (will be retried on app startup)
  })
}