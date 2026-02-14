#' DataStore R6 Class
#'
#' A production-grade R6 class for managing mutable data state with immutable
#' original snapshots, DuckDB persistence, and type-safe cell updates.
#'
#' @description
#' Implements single source of truth pattern for Shiny applications:
#' - Loads data from DuckDB on initialization
#' - Maintains original (immutable) and data (mutable) snapshots
#' - Provides type-safe cell updates with validation
#' - Supports revert to original state
#' - Generates summary statistics for UI display
#'
#' @section Usage:
#' ```r
#' store <- DataStore$new()
#' store$update_cell(row = 1, col = "mpg", value = 22.5)
#' store$revert()
#' store$summary()
#' ```
#'
#' @export
DataStore <- R6::R6Class(
  "DataStore",
  public = list(
    #' @field con DuckDB connection object (DBI connection)
    con = NULL,
    #' @field data Working data frame currently in use
    data = NULL,
    #' @field original Original baseline snapshot of the data
    original = NULL,
    #' Initialize DataStore
    #'
    #' @description
    #' This function does following tasks:
    #' 1. Locate the bundled DuckDB file located in inst/extdata/
    #'    Use: system.file("extdata", "mtcars.duckdb", package = "<your-package>")
    #'
    #' 2. Establish a DuckDB connection using DBI::dbConnect()
    #'    (store the connection in self$con)
    #'
    #' 3. Query the "mtcars" table from the database
    #'    using DBI::dbGetQuery()
    #'
    #' 4. Store the result in:
    #'    - self$data     (the working, mutable copy)
    #'    - self$original (the immutable original snapshot)
    #'
    #' @return Invisible self for method chaining
    #' @examples
    #' \dontrun{
    #' store <- DataStore$new()
    #' }
    #'
    initialize = function() {
      tryCatch({
        private$db_path <- validate_db_path()

        self$con <- establish_duckdb_connection(private$db_path, read_only = FALSE)

        new_rownames <- c("Mazda RX4", "Mazda RX4 Wag", "Datsun 710",
                          "Hornet 4 Drive", "Hornet Sportabout", "Valiant",
                          "Duster 360", "Merc 240D", "Merc 230",
                          "Merc 280", "Merc 280C", "Merc 450SE",
                          "Merc 450SL", "Merc 450SLC", "Cadillac Fleetwood",
                          "Lincoln Continental", "Chrysler Imperial", "Fiat 128",
                          "Honda Civic", "Toyota Corolla", "Toyota Corona",
                          "Dodge Challenger", "AMC Javelin", "Camaro Z28",
                          "Pontiac Firebird", "Fiat X1-9", "Porsche 914-2",
                          "Lotus Europa", "Ford Pantera L", "Ferrari Dino",
                          "Maserati Bora", "Volvo 142E"
        )
        query_result <- load_mtcars_data(self$con, table = "mtcars", default_rownames = new_rownames)
        self$original <- data.frame(query_result, check.names = TRUE)
        self$data <- data.frame(query_result, check.names = TRUE)
        private$modified_cells <- 0

        cli::cli_inform("DataStore initialized: {nrow(self$data)} rows loaded from DuckDB")
      }, error = function(e) {
        # Cleanup on failure: disconnect + unlink temp file
        if (!is.null(self$con)) {
          tryCatch({
            DBI::dbDisconnect(self$con, shutdown = TRUE)
          }, error = function(x) NULL)
        }

        cli::cli_abort(c(
          "DataStore initialization failed",
          "x" = "{conditionMessage(e)}"
        ))
      })

      invisible(self)
    },
    #' @description Reset the working data (self$data) back to the original snapshot.
    #'
    #' Expected behavior:
    #' - self$data should become identical to self$original
    #' - Does not affect the database or the connection
    #'
    #' @return Invisible self for method chaining
    #' @examples
    #' \dontrun{
    #' store$revert()
    #' }
    revert = function() {
      tryCatch({
        checkmate::assert_data_frame(self$original, null.ok = FALSE)

        reverted_data <- tryCatch({
          data.frame(self$original, check.names = FALSE)
        }, error = function(e) {
          cli::cli_abort(c(
            "Failed to revert data",
            "x" = "Error during deep copy: {conditionMessage(e)}"
          ))
        })

        self$data <- reverted_data
        private$modified_cells <- 0
        private$.summary_cache <- NULL  # Invalidate cache on revert

        cli::cli_inform("Data reverted to original state ({nrow(self$data)} rows)")
        invisible(self)
      }, error = function(e) {
        cli::cli_abort(c("Revert operation failed", "x" = "{conditionMessage(e)}"))
      })
    },
    #' @description
    #' Returns human-readable summary for UI display with validation and error handling.
    #'
    #'
    #' @return List with summary components (message, rows, cols, numeric_means).
    #'   All fields always present; numeric_means is NULL if no numeric columns.
    #'
    #' @examples
    #' \dontrun{
    #' store$summary()
    #' }
    summary = function() {
      tryCatch({
        if (!is.null(private$.summary_cache) && private$modified_cells == 0) {
          return(private$.summary_cache)
        }

        validate_summary_data(self$data)

        numeric_cols <- detect_numeric_columns(self$data)

        numeric_means <- if (length(numeric_cols) > 0) {
          calculate_column_means(self$data, numeric_cols)
        } else {
          NULL
        }

        summary_list <- list(
          message = sprintf("Rows: %d | Columns: %d", nrow(self$data), ncol(self$data)),
          rows = nrow(self$data),
          cols = ncol(self$data),
          numeric_means = numeric_means
        )

        private$.summary_cache <<- summary_list

        cli::cli_inform("Summary generated for {nrow(self$data)} x {ncol(self$data)} dataset")
        summary_list
      }, error = function(e) {
        cli::cli_abort(c(
          "Failed to generate summary",
          "x" = "{conditionMessage(e)}"
        ))
      })
    },
    #' @description
    #' Type-safe cell update with validation. Ensures data type consistency
    #' with original dataset. Implements deterministic single-cell edit pattern
    #' for predictable state management. Uses granular validation per phase.
    #'
    #' @param row Integer row index (1-based)
    #' @param col Column name (character) or index (integer)
    #' @param value New value to assign (will be coerced to match column type)
    #'
    #' @return Invisible TRUE on success, throws cli_abort on validation failure
    #' @examples
    #' \dontrun{
    #' store$update_cell(1, "mpg", 22.5)
    #' store$update_cell(2, 4, 120)  # Using column index
    #' }
    update_cell = function(row, col, value) {
      validate_data(self$data)

      validate_row(row, self$data)

      col_name <- validate_column(col, self$data)

      if (is.character(value) && identical(value, "")) {
        cli::cli_abort("Value cannot be empty for column '{col_name}'")
      }

      col_type <- class(self$original[[col_name]])[1]
      if (col_type %in% c("numeric", "integer")) {
        if (is.na(suppressWarnings(as.numeric(value)))) {
          cli::cli_abort("Invalid numeric value '{value}' for column '{col_name}'")
        }
      }

      coerced_value <- coerce_value(value, col_name, self$original)

      validate_no_na_loss(coerced_value, value, col_name)

      self$data[row, col_name] <- coerced_value

      private$modified_cells <- private$modified_cells + 1
      private$.summary_cache <- NULL  # Invalidate cache on data change

      invisible(TRUE)
    },
    #' @description
    #' Persists current working data back to DuckDB table with full validation.
    #' Implements granular validation phases with deterministic checks (checkmate)
    #' and risky operations in try-catch blocks. Overwrites entire table with current state.
    #' Resets modified cells counter and updates original snapshot after successful save.
    #' Uses bifurcated error handling: checkmate assertions -> try-catch for DB operations
    #' -> cli messaging for context.
    #'
    #' @return Invisible self for method chaining
    #' @examples
    #' \dontrun{
    #' store$save()
    #' }
    save = function() {
      tryCatch({
        validate_save_connection(self$con)

        validate_save_data(self$data)
        validate_save_structure(self$data, self$original)
        delete_mtcars_table(self$con)

        write_mtcars_to_db(self$con, self$data)
        self$original <- data.frame(self$data, check.names = FALSE)

        private$modified_cells <- 0

        cli::cli_inform("Data saved to DuckDB: {nrow(self$data)} rows saved successfully")
        invisible(self)
      }, error = function(e) {
        cli::cli_abort(c(
          "Save operation failed",
          "x" = "{conditionMessage(e)}"
        ))
      })

    },
    #' @description
    #' Returns the number of cells that have been modified since last save/revert.
    #'
    #' @return Integer count of modified cells
    #' @examples
    #' \dontrun{
    #' count <- store$get_modified_count()
    #' }
    get_modified_count = function() {
      private$modified_cells
    }
  ),

  private = list(
    db_path = NULL,
    modified_cells = 0,
    .summary_cache = NULL,
    finalize = function() {
      # Disconnect from DuckDB
      if (!is.null(self$con)) {
        tryCatch({
          DBI::dbDisconnect(self$con, shutdown = TRUE)
          cli::cli_inform("DuckDB connection closed")
        }, error = function(e) {
          cli::cli_warn("Error closing DuckDB connection: {conditionMessage(e)}")
        })
      }

    }
  )
)
