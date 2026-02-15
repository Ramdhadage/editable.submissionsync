#' Reset mtcars DuckDB Database
#'
#' @description
#' Fixture function that regenerates the mtcars.duckdb database file
#' with original R mtcars dataset. Properly converts column types to match
#' application expectations (factors for cyl/vs/gear/carb, logical for am).
#'
#' Cleans up associated .wal and .tmp files to ensure fresh state.
#' Compatible with testthat 3.x.
#'
#' @return Invisibly returns NULL (testthat fixture convention)
#'
#' @keywords internal
#'
with_fresh_mtcars_db <- function() {
  db_path <- system.file("extdata", "mtcars.duckdb", package = "editable.submissionsync")

  if (!file.exists(dirname(db_path))) {
    cli::cli_abort("DuckDB directory not found: {dirname(db_path)}")
  }

  wal_file <- paste0(db_path, ".wal")
  tmp_file <- paste0(db_path, ".tmp")

  if (file.exists(wal_file)) {
    unlink(wal_file)
  }
  if (file.exists(tmp_file)) {
    unlink(tmp_file)
  }

  if (file.exists(db_path)) {
    unlink(db_path)
  }

  tryCatch({
    con <- DBI::dbConnect(
      duckdb::duckdb(),
      dbdir = db_path,
      read_only = FALSE
    )

    mtcars_data <- mtcars

    mtcars_data$am <- as.logical(mtcars_data$am)
    mtcars_data$vs <- as.factor(mtcars_data$vs)
    mtcars_data$cyl <- as.factor(mtcars_data$cyl)
    mtcars_data$gear <- as.factor(mtcars_data$gear)
    mtcars_data$carb <- as.factor(mtcars_data$carb)

    DBI::dbWriteTable(
      con,
      "mtcars",
      mtcars_data,
      overwrite = TRUE
    )

    DBI::dbDisconnect(con, shutdown = TRUE)

    cli::cli_inform("Fresh mtcars database created")

  }, error = function(e) {
    if (!is.null(con)) {
      tryCatch({
        DBI::dbDisconnect(con, shutdown = TRUE)
      }, error = function(x) NULL)
    }

    if (file.exists(db_path)) {
      unlink(db_path)
    }
    if (file.exists(wal_file)) {
      unlink(wal_file)
    }

    cli::cli_abort(c(
      "Failed to create fresh mtcars database",
      "x" = "{conditionMessage(e)}"
    ))
  })

  invisible(NULL)
}
