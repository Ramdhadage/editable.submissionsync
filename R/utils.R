#' Validate DuckDB Path
#'
#' @description
#' Validates the existence and readability of the DuckDB bundle file.
#' Uses checkmate assertions for deterministic validation.
#'
#' @param package Character. Package name where bundle is located.
#'   Default: "r6.assignment"
#' @param subdir Character. Subdirectory within package inst folder.
#'   Default: "extdata"
#' @param filename Character. DuckDB file name.
#'   Default: "mtcars.duckdb"
#'
#' @return Character. Validated path to DuckDB file. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' db_path <- validate_db_path()
#' }
#' @keywords internal
validate_db_path <- function(package = "editable.submissionsync",
                             subdir = "extdata",
                             filename = "mtcars") {
  tryCatch({
    # Resolve path from package installation
    db_path <- system.file(subdir, paste0(filename,".duckdb") , package = package)

    # Validation: Check if path is non-empty and file exists
    checkmate::assert_file_exists(db_path, access = "r")

    db_path
  }, error = function(e) {
    cli::cli_abort(c(
      "DuckDB bundle file not found",
      "i" = "Package: {package}",
      "i" = "Expected location: {package}/inst/{subdir}/{filename}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}



#' Establish DuckDB Connection
#'
#' @description
#' Establishes a DBI connection to DuckDB database with error handling.
#' Connection is left open for subsequent operations; caller is responsible
#' for cleanup via DBI::dbDisconnect().
#'
#' @param temp_db Character. Path to DuckDB database file.
#' @param read_only Logical. Whether to open database in read-only mode.
#'   Default: FALSE (read-write mode)
#'
#' @return DBI connection object. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' con <- establish_duckdb_connection(temp_db)
#' }
#' @keywords internal
establish_duckdb_connection <- function(temp_db, read_only = FALSE) {
  tryCatch({
    db_dir <- dirname(temp_db)
    checkmate::assert_directory_exists(db_dir, access = "w")
    checkmate::assert_file_exists(temp_db, access = "r")
    con <- DBI::dbConnect(
      duckdb::duckdb(),
      dbdir = temp_db,
      read_only = read_only
    )

    con
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to establish DuckDB connection",
      "i" = "Database path: {temp_db}",
      "i" = "Read-only mode: {read_only}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}

#' Load Data from DuckDB Table
#'
#' @description
#' Reads entire table from DuckDB database with type-safe retrieval.
#' Uses DBI::dbReadTable() for automatic type preservation.
#' On failure, returns empty data.frame() and warns (graceful degradation).
#'
#' @param con DBI connection object (active DuckDB connection).
#' @param table Character. Name of table to load.
#'   Default: "mtcars"
#'
#' @return data.frame. Table data with proper column types. Returns empty
#'   data.frame() on query failure (warns but does not abort).
#'
#' @examples
#' \dontrun{
#' data <- load_mtcars_data(con, table = "mtcars")
#' }
#' @keywords internal
load_data <- function(con, table = "adsl", default_rownames = NULL) {
  tryCatch({
    # Read table with type preservation
    result <-  DBI::dbReadTable(con, table)
    # result <- set_column_type(result)
    return(result)
  }, error = function(e) {
    cli::cli_warn(c(
      "Failed to load table from DuckDB, initializing with empty dataset",
      "i" = "Table: {table}",
      "x" = "Error: {conditionMessage(e)}"
    ))

    # Return empty data.frame instead of aborting (graceful degradation)
    data.frame()
  })
}
#' Convert mtcars columns to appropriate data types
#'
#' Transforms specific columns in a data frame to more appropriate data types:
#' - 'am' column to logical (automatic vs manual transmission)
#' - 'vs', 'cyl', 'gear', 'carb' columns to factors
#'
#' @param data A data frame to transform
#' @return A data frame with transformed column types
#' @examples
#' \dontrun{
#' transformed_mtcars <- set_mtcars_column_type(mtcars)
#' }
#' @keywords internal
set_column_type <- function(data) {
  if (!is.data.frame(data)) {
    stop("Input must be a data frame")
  }

  # Apply transformations
  for (col_name in names(data)) {
    if (col_name %in% "am") {
      data[[col_name]] <- as.logical(data[[col_name]])
    } else if (col_name %in% c("vs", "cyl", "gear", "carb")) {
      data[[col_name]] <- as.factor(data[[col_name]])
    }
  }

  return(data)
}



#' Validate Data Frame Exists and Is Valid
#'
#' @description
#' Validates that data frame exists and is of correct type.
#' Used in update_cell validation chain.
#'
#' @param data data.frame. The data frame to validate.
#'
#' @return Invisible NULL on success. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' validate_data(mtcars)
#' }
#' @keywords internal
validate_data <- function(data) {
  tryCatch({
    checkmate::assert_data_frame(data, null.ok = FALSE)
    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "No data loaded or invalid data structure",
      "x" = "Expected: data.frame object",
      "i" = "Error: {conditionMessage(e)}"
    ))
  })
}

#' Validate Row Index
#'
#' @description
#' Validates row index is within valid bounds (1-based).
#' Used in update_cell validation chain.
#'
#' @param row Integer. Row index to validate.
#' @param data data.frame. Data frame for bounds checking.
#'
#' @return Invisible NULL on success. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' validate_row(1, mtcars)
#' }
#' @keywords internal
validate_row <- function(row, data) {
  tryCatch({
    # Validate is integer-like
    checkmate::assert_integerish(row, len = 1, null.ok = FALSE)

    # Validate bounds
    if (row < 1 || row > nrow(data)) {
      stop("Row index out of bounds")
    }

    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "Invalid row index",
      "i" = "Row: {row}",
      "i" = "Valid range: 1-{nrow(data)}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}

#' Validate and Normalize Column Identifier
#'
#' @description
#' Validates column identifier (character name or numeric index) and
#' returns normalized column name. Converts numeric indices to names.
#' Used in update_cell validation chain.
#'
#' @param col Character or integer. Column name or index.
#' @param data data.frame. Data frame for validation and lookup.
#'
#' @return Character. Normalized column name. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' validate_column("mpg", mtcars)
#' validate_column(1, mtcars)  # Returns "mpg"
#' }
#' @keywords internal
validate_column <- function(col, data) {
  tryCatch({
    # If numeric: validate bounds and convert to name
    if (is.numeric(col)) {
      checkmate::assert_integerish(col, len = 1, null.ok = FALSE)

      if (col < 1 || col > ncol(data)) {
        stop("Column index out of bounds")
      }

      col_name <- names(data)[col]
    } else {
      # If character: validate existence
      col_name <- as.character(col)
      checkmate::assert_choice(col_name, choices = names(data))
    }

    col_name
  }, error = function(e) {
    if (is.numeric(col)) {
      cli::cli_abort(c(
        "Invalid column index",
        "i" = "Index: {col}",
        "i" = "Valid range: 1-{ncol(data)}",
        "x" = "Error: {conditionMessage(e)}"
      ))
    } else {
      cli::cli_abort(c(
        "Column not found in dataset",
        "i" = "Requested column: {col}",
        "i" = "Available columns: {paste(names(data), collapse = ', ')}",
        "x" = "Error: {conditionMessage(e)}"
      ))
    }
  })
}

#' Coerce Value to Column Type
#'
#' @description
#' Type-safe coercion of value to match original column type.
#' Preserves column type schema from original data.frame.
#' Used in update_cell validation chain.
#'
#' @param value New value to coerce.
#' @param col_name Character. Name of target column.
#' @param original_data data.frame. Original data frame for type reference.
#'
#' @return Coerced value with correct type. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' coerce_value(22.5, "mpg", mtcars)
#' }
#' @importFrom methods as
#' @keywords internal
coerce_value <- function(value, col_name, original_data) {
  tryCatch({
    # Get expected type from original data
    original_type <- class(original_data[[col_name]])[1]

    # Coerce with type-specific handling
    coerced <- suppressWarnings({
      switch(original_type,
             "numeric" = as.numeric(value),
             "integer" = as.integer(value),
             "character" = as.character(value),
             "logical" = as.logical(value),
             "factor" = factor(value, levels = levels(original_data[[col_name]])),
             as(value, original_type)
      )
    })
    coerced
  }, error = function(e) {
    cli::cli_abort(c(
      "Type coercion failed",
      "i" = "Column: {col_name}",
      "i" = "Value: {value}",
      "i" = "Expected type: {class(original_data[[col_name]])[1]}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}

#' Validate No Data Loss from Type Coercion
#'
#' @description
#' Validates that type coercion did not introduce unwanted NA values.
#' Allows valid NA transitions (NA->NA), but prevents data loss (value->NA).
#' Used in update_cell validation chain.
#'
#' @param coerced_value Coerced value from type conversion.
#' @param original_value Original value before coercion.
#' @param col_name Character. Name of column being updated.
#'
#' @return Invisible TRUE on success. Throws cli_abort on failure.
#'
#' @examples
#' \dontrun{
#' validate_no_na_loss(22.5, 22.5, "mpg")
#' }
#' @keywords internal
validate_no_na_loss <- function(coerced_value, original_value, col_name) {
  tryCatch({
    # Check for unwanted NA introduction (data loss)
    if (is.na(coerced_value) && !is.na(original_value)) {
      stop("Type coercion resulted in NA")
    }

    invisible(TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Type coercion resulted in data loss",
      "i" = "Column: {col_name}",
      "i" = "Original value: {original_value}",
      "i" = "Coerced value: {coerced_value}",
      "x" = "Cannot convert {original_value} to valid value for column {col_name}"
    ))
  })
}
#' Validate Summary Data
#'
#' @description
#' Validates that data exists and is a valid data.frame before summary calculations.
#' Uses deterministic checkmate assertions to fail-fast on invalid input.
#'
#' @param data Data frame to validate
#'
#' @return Invisible NULL. Throws cli_abort if validation fails.
#'
#' @examples
#' \dontrun{
#' validate_summary_data(mtcars)  # Passes
#' validate_summary_data(NULL)    # Throws cli_abort
#' }
#' @keywords internal
validate_summary_data <- function(data) {
  tryCatch({
    checkmate::assert_data_frame(data, null.ok = FALSE, min.rows = 1)
  }, error = function(e) {
    cli::cli_abort(c(
      "Invalid data for summary",
      "x" = "Data must be a non-empty data.frame",
      "i" = "Error: {conditionMessage(e)}"
    ))
  })
  invisible(NULL)
}

#' Detect Numeric Columns
#'
#' @description
#' Safely identifies columns with numeric data type.
#' Returns gracefully with empty vector if no numeric columns found or on error.
#' Useful for conditional mean calculations in summaries.
#'
#' @param data Data frame to analyze
#'
#' @return Character vector of numeric column names. Returns empty character(0)
#'   if no numeric columns or on calculation error.
#'
#' @examples
#' \dontrun{
#' detect_numeric_columns(mtcars)
#' }
#' @keywords internal
detect_numeric_columns <- function(data) {
  tryCatch({
    # Safely detect numeric columns with sapply
    is_numeric <- sapply(data, is.numeric, simplify = TRUE, USE.NAMES = TRUE)
    # Return column names where is.numeric is TRUE
    names(is_numeric)[is_numeric]
  }, error = function(e) {
    # Graceful degradation: log warning and return empty vector
    cli::cli_warn("Failed to detect numeric columns: {conditionMessage(e)}")
    character(0)
  })
}

#' Calculate Column Means
#'
#' @description
#' Calculates means for specified numeric columns.
#' Uses colMeans with NA removal for robust statistics.
#' Throws cli_abort on calculation failure with rich error context.
#'
#' @param data Data frame containing columns to summarize
#' @param numeric_cols Character vector of column names (should be numeric)
#'
#' @return Numeric vector of means (names = column names).
#'   Throws cli_abort if calculation fails.
#'
#' @examples
#' \dontrun{
#' calculate_column_means(mtcars, c("mpg", "hp"))
#' }
#' @keywords internal
calculate_column_means <- function(data, numeric_cols) {
  tryCatch({
    # Verify numeric_cols is non-empty
    if (length(numeric_cols) == 0) {
      return(NULL)
    }

    # Calculate means with NA removal
    colMeans(data[, numeric_cols, drop = FALSE], na.rm = TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to calculate column means",
      "i" = "Columns: {paste(numeric_cols, collapse = ', ')}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}

#' Validate Save Connection
#'
#' @description
#' Validates that a DBI connection object exists and is valid before save operations.
#' Uses deterministic checkmate assertions to fail-fast on invalid connection.
#'
#' @param con DBI connection object to validate
#'
#' @return Invisible NULL. Throws cli_abort if validation fails.
#'
#' @examples
#' \dontrun{
#' validate_save_connection(con)  # Passes if valid
#' validate_save_connection(NULL) # Throws cli_abort
#' }
#' @keywords internal
validate_save_connection <- function(con) {
  tryCatch({
    # Check if connection exists and is valid DBI connection
    if (is.null(con)) {
      stop("Connection is NULL")
    }
    if (!inherits(con, "DBIConnection")) {
      stop("Not a valid DBI connection object")
    }
    if (!DBI::dbIsValid(con)) {
      stop("Connection is not valid (closed or broken)")
    }
  }, error = function(e) {
    cli::cli_abort(c(
      "Invalid database connection for save",
      "x" = "{conditionMessage(e)}"
    ))
  })
  invisible(NULL)
}

#' Validate Save Data
#'
#' @description
#' Validates that data exists and is a valid, non-empty data.frame before save.
#' Uses deterministic checkmate assertions to fail-fast on invalid data.
#'
#' @param data Data frame to validate
#'
#' @return Invisible NULL. Throws cli_abort if validation fails.
#'
#' @examples
#' \dontrun{
#' validate_save_data(mtcars)  # Passes
#' validate_save_data(NULL)    # Throws cli_abort
#' }
#' @keywords internal
validate_save_data <- function(data) {
  tryCatch({
    checkmate::assert_data_frame(data, null.ok = FALSE, min.rows = 1)
  }, error = function(e) {
    cli::cli_abort(c(
      "Invalid data for save operation",
      "x" = "Data must be a non-empty data.frame",
      "i" = "Error: {conditionMessage(e)}"
    ))
  })
  invisible(NULL)
}

#' Validate Save Data Structure (Columns and Rows)
#'
#' @description
#' Validates that current data structure matches original structure.
#' Ensures no required columns have been removed/altered AND row count is preserved.
#' Critical for data integrity: prevents silent column/row loss before database write.
#'
#' @param data Current data frame to validate
#' @param original Original data frame structure reference
#'
#' @return Invisible NULL. Throws cli_abort if validation fails.
#'
#' @keywords internal
validate_save_structure <- function(data, original) {
  tryCatch({
    # Validation 1: Check column structure (names and count)
    current_cols <- names(data)
    original_cols <- names(original)

    if (!identical(current_cols, original_cols)) {
      missing_cols <- setdiff(original_cols, current_cols)
      extra_cols <- setdiff(current_cols, original_cols)

      error_msg <- character(0)
      if (length(missing_cols) > 0) {
        error_msg <- c(error_msg, paste("Missing columns:", paste(missing_cols, collapse = ", ")))
      }
      if (length(extra_cols) > 0) {
        error_msg <- c(error_msg, paste("Extra columns:", paste(extra_cols, collapse = ", ")))
      }

      stop(paste(error_msg, collapse = "; "))
    }

    # Validation 2: Check row count (data integrity)
    current_rows <- nrow(data)
    original_rows <- nrow(original)

    if (current_rows != original_rows) {
      stop(sprintf("Row count mismatch: expected %d rows, found %d rows",
                   original_rows, current_rows))
    }

    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "Data structure does not match original",
      "x" = "{conditionMessage(e)}",
      "i" = "Original: {nrow(original)} rows x {ncol(original)} columns",
      "i" = "Current: {nrow(data)} rows x {ncol(data)} columns",
      "i" = "Original columns: {paste(names(original), collapse = ', ')}",
      "i" = "Current columns: {paste(names(data), collapse = ', ')}"
    ))
  })
}


#' Delete Existing mtcars Table
#'
#' @description
#' Safely deletes the mtcars table from DuckDB if it exists.
#' Uses try-catch to handle database errors gracefully.
#' Uses IF EXISTS to prevent errors if table doesn't exist.
#'
#' @param con DBI connection to DuckDB database
#'
#' @return Invisible NULL. Throws cli_abort on deletion failure.
#'
#' @examples
#' \dontrun{
#' delete_mtcars_table(con)
#' }
#' @keywords internal
delete_mtcars_table <- function(con) {
  tryCatch({
    # DROP TABLE IF EXISTS is safe - no error if table doesn't exist
    DBI::dbExecute(con, "DROP TABLE IF EXISTS mtcars")
    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to delete existing mtcars table",
      "x" = "Database error: {conditionMessage(e)}"
    ))
  })
}

#' Write mtcars Data to DuckDB
#'
#' @description
#' Writes data frame to mtcars table in DuckDB database.
#' Uses try-catch to handle write failures with error context.
#'
#' @param con DBI connection to DuckDB database
#' @param data Data frame to write (should be same structure as original)
#'
#' @return Invisible NULL. Throws cli_abort on write failure.
#'
#' @examples
#' \dontrun{
#' write_mtcars_to_db(con, data)
#' }
#' @keywords internal
write_mtcars_to_db <- function(con, data) {
  tryCatch({
    DBI::dbWriteTable(con, "mtcars", data, overwrite = TRUE)
    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to write data to DuckDB",
      "i" = "Rows: {nrow(data)}",
      "i" = "Columns: {ncol(data)}",
      "x" = "Database error: {conditionMessage(e)}"
    ))
  })
}

#' Clean ANSI Escape Codes from Error Messages
#'
#' @description
#' Removes ANSI escape codes (color formatting) from error messages.
#' Useful for displaying CLI-generated error messages in Shiny UI where ANSI codes
#' would appear as visible characters.
#'
#' @param error_msg Character. Error message potentially containing ANSI codes.
#'
#' @return Character. Error message with ANSI codes removed.
#'
#' @examples
#' \dontrun{
#' clean_error_message("\u001b[31mError message\u001b[0m")
#' # Returns: "Error message"
#' }
#' @keywords internal
clean_error_message <- function(error_msg) {
  gsub("\u001b\\[[0-9;]*m", "", error_msg)
}

#' Get or Initialize DataStore Cache
#' @description
#' Retrieves the cached DataStore instance from the .cache_env environment.
#' If it doesn't exist, initializes a new DataStore and stores it in the cache.
#' If it already exists, calls the revert() method to reset it to initial state.
#' This function ensures that the DataStore is always available and in a consistent state. # nolint
#' @keywords internal
get_cached_store <- function() {
  if (!exists(".store", envir = .cache_env, inherits = FALSE)) {
    .cache_env$.store <- DataStore$new()
    .cache_env$.init_time <- Sys.time()
  } else {
    .cache_env$.store$revert()
  }
  .cache_env$.store
}
