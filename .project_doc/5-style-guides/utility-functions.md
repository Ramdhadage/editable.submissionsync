# Utility Functions Style Guide

## Overview

Utility functions in editable are **single-responsibility, pure functions** that support validation, type coercion, and data operations. They are designed to be:
- Deterministic (same input → same output)
- Focused on one concern
- Composable (used in validation chains)
- Well-documented with roxygen

## File Convention

**File**: `R/utils.R`

All utilities grouped in single file, organized by concern:
- Validation functions (prefixed `validate_*`)
- Type functions (prefixed `coerce_*`, `detect_*`)
- Data functions (prefixed `load_*`, `write_*`, `set_*`, `calculate_*`)
- Message functions (prefixed `clean_*`)

## Validation Function Pattern

### Basic Validation

```r
#' Validate Row Index
#'
#' @description
#' Ensures row index is within valid bounds (1-based indexing).
#' Used in update_cell validation chain.
#'
#' @param row Integer. Row index to validate.
#' @param data data.frame. Data frame for bounds checking.
#'
#' @return Invisible NULL on success. Throws cli_abort on failure.
#'
#' @keywords internal
validate_row <- function(row, data) {
  tryCatch({
    # Deterministic check
    checkmate::assert_integerish(row, len = 1, null.ok = FALSE)
    
    # Bounds check
    if (row < 1 || row > nrow(data)) {
      stop("Row index out of bounds")
    }
    
    invisible(NULL)
  }, error = function(e) {
    # Rich error message
    cli::cli_abort(c(
      "Invalid row index",
      "i" = "Row: {row}",
      "i" = "Valid range: 1-{nrow(data)}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}
```

**Pattern:**
- `@keywords internal` (not exported if validation-only)
- Checkmate for deterministic checks
- `tryCatch` for error context
- Return `invisible(NULL)` on success
- Throw `cli::cli_abort` with context on failure

### Multi-choice Validation

```r
#' Validate and Normalize Column Identifier
#'
#' @description
#' Accepts column name (character) or index (numeric).
#' Normalizes to column name for consistency.
#' Used in update_cell validation chain.
#'
#' @param col Character or integer. Column name or 1-based index.
#' @param data data.frame. Data frame for validation.
#'
#' @return Character. Normalized column name.
#'   Throws cli_abort on invalid column.
#'
#' @keywords internal
validate_column <- function(col, data) {
  tryCatch({
    if (is.numeric(col)) {
      # Integer index path
      checkmate::assert_integerish(col, len = 1, null.ok = FALSE)
      
      if (col < 1 || col > ncol(data)) {
        stop("Column index out of bounds")
      }
      
      col_name <- names(data)[col]
    } else {
      # Character name path
      col_name <- as.character(col)
      checkmate::assert_choice(col_name, choices = names(data))
    }
    
    col_name
  }, error = function(e) {
    # Different error messages for different input types
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
```

**Pattern:**
- Handle multiple input types separately
- Return normalized form (column name, not index)
- Customize error messages per input type
- Include available options in error

### Graceful Degradation

```r
#' Detect Numeric Columns
#'
#' @description
#' Safely identifies numeric columns.
#' Returns empty character vector on failure (graceful degradation).
#'
#' @param data data.frame. Data frame to analyze.
#'
#' @return Character vector of numeric column names.
#'   Returns empty character(0) if none found or on error.
#'
#' @keywords internal
detect_numeric_columns <- function(data) {
  tryCatch({
    is_numeric <- sapply(data, is.numeric, simplify = TRUE, USE.NAMES = TRUE)
    names(is_numeric)[is_numeric]
  }, error = function(e) {
    cli::cli_warn("Failed to detect numeric columns: {conditionMessage(e)}")
    character(0)  # Empty vector, not error
  })
}
```

**Pattern:**
- Detect validation failures without aborting
- Log warnings for debugging
- Return sensible empty/default value
- Used when feature is non-critical

## Type Coercion Functions

```r
#' Coerce Value to Column Type
#'
#' @description
#' Type-safe coercion preserving original schema.
#' Handles numeric, integer, character, logical, factor.
#'
#' @param value New value to coerce.
#' @param col_name Character. Target column name.
#' @param original_data data.frame. Reference for original types.
#'
#' @return Coerced value with correct type.
#'   Throws cli_abort on coercion failure.
#'
#' @keywords internal
coerce_value <- function(value, col_name, original_data) {
  tryCatch({
    # Get expected type from original schema
    original_type <- class(original_data[[col_name]])[1]
    
    # Type-specific coercion
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
#' Ensures coercion did not silently introduce NA.
#' Allows NA→NA (valid transition), prevents value→NA (data loss).
#'
#' @param coerced_value Result of type coercion.
#' @param original_value Original user input.
#' @param col_name Character. Column being updated (for errors).
#'
#' @return Invisible TRUE on success.
#'   Throws cli_abort if data loss detected.
#'
#' @keywords internal
validate_no_na_loss <- function(coerced_value, original_value, col_name) {
  tryCatch({
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
```

**Pattern:**
- Reference types from original data (source of truth)
- Use `switch` for type-specific handling
- Wrap in `suppressWarnings()` to ignore coercion warnings
- Post-coercion validation (NA detection)
- Thread error context through validation chain

## Data Manipulation Functions

### Data Loading

```r
#' Load Data from DuckDB Table
#'
#' @description
#' Reads entire table from DuckDB with type-safe retrieval.
#' Applies domain-specific column type conversions.
#'
#' @param con DBI connection object (active DuckDB connection).
#' @param table Character. Name of table to load.
#' @param default_rownames Character vector. Optional rownames to add.
#'
#' @return data.frame. Table data with proper column types.
#'   Returns empty data.frame on failure (graceful degradation).
#'
#' @keywords internal
load_mtcars_data <- function(con, table = "mtcars", default_rownames = NULL) {
  tryCatch({
    # Read table from DB
    result <- DBI::dbReadTable(con, table)
    
    # Restore rownames if needed
    if (is.null(rownames(result)) || all(rownames(result) == seq_len(nrow(result))) && !("MODEL" %in% names(result))) {
      if (!is.null(default_rownames) && length(default_rownames) == nrow(result)) {
        result <- cbind(MODEL = default_rownames, result, stringsAsFactors = FALSE)
      }
    }
    
    # Apply type conversions
    result <- set_mtcars_column_type(result)
    return(result)
  }, error = function(e) {
    cli::cli_warn(c(
      "Failed to load table from DuckDB, initializing with empty dataset",
      "i" = "Table: {table}",
      "x" = "Error: {conditionMessage(e)}"
    ))
    data.frame()  # Empty fallback
  })
}
```

### Column Type Transformation

```r
#' Convert mtcars Columns to Appropriate Data Types
#'
#' @description
#' Applies domain-specific type transformations:
#' - 'am' (automatic transmission) → logical
#' - 'vs', 'cyl', 'gear', 'carb' → factor (categorical)
#'
#' @param data data.frame. Data frame to transform.
#'
#' @return data.frame. With transformed column types.
#'
#' @keywords internal
set_mtcars_column_type <- function(data) {
  if (!is.data.frame(data)) {
    stop("Input must be a data frame")
  }
  
  for (col_name in names(data)) {
    if (col_name %in% "am") {
      data[[col_name]] <- as.logical(data[[col_name]])
    } else if (col_name %in% c("vs", "cyl", "gear", "carb")) {
      data[[col_name]] <- as.factor(data[[col_name]])
    }
  }
  
  return(data)
}
```

**Pattern:**
- Transform types based on domain knowledge
- Apply to loaded data for consistency
- Include in initialization and save cycles
- Document transformation rules

### Summary Calculations

```r
#' Calculate Column Means
#'
#' @description
#' Computes means for specified numeric columns.
#' Uses colMeans with NA removal for robustness.
#'
#' @param data data.frame. Data to summarize.
#' @param numeric_cols Character vector. Column names to average.
#'
#' @return Numeric vector of means (names = column names).
#'
#' @keywords internal
calculate_column_means <- function(data, numeric_cols) {
  tryCatch({
    if (length(numeric_cols) == 0) {
      return(NULL)
    }
    
    colMeans(data[, numeric_cols, drop = FALSE], na.rm = TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to calculate column means",
      "i" = "Columns: {paste(numeric_cols, collapse = ', ')}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}
```

**Pattern:**
- Zero-length input returns NULL
- Error on actual computation failures
- Document NA handling

## Error Message Utilities

```r
#' Clean ANSI Escape Codes from Error Messages
#'
#' @description
#' Removes ANSI color/formatting codes from error messages.
#' Necessary for displaying cli-generated errors in Shiny UI.
#'
#' @param error_msg Character. Message potentially with ANSI codes.
#'
#' @return Character. Error message with codes removed.
#'
#' @keywords internal
clean_error_message <- function(error_msg) {
  gsub("\u001b\\[[0-9;]*m", "", error_msg)
}
```

**Pattern:**
- Remove formatting artifacts before UI display
- Use in error notification handlers

## Connection & Database Functions

```r
#' Establish DuckDB Connection
#'
#' @param temp_db Character. Path to DuckDB file.
#' @param read_only Logical. Open in read-only mode?
#'
#' @return DBI connection object.
#'
#' @keywords internal
establish_duckdb_connection <- function(temp_db, read_only = FALSE) {
  tryCatch({
    db_dir <- dirname(temp_db)
    checkmate::assert_directory_exists(db_dir, access = "w")
    
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
```

## Documentation Standards

```r
#' Function Name (Title Case, Verb + Noun)
#'
#' @description
#' One-sentence summary of what function does.
#'
#' @details
#' Extended explanation if needed. Behavior notes, side effects, etc.
#'
#' @param param1 Type. What it is and constraints.
#' @param param2 Type. What it is and constraints.
#'
#' @return Type. What is returned, format, NULL on error, etc.
#'
#' @examples
#' \dontrun{
#' result <- my_function(arg1, arg2)
#' }
#'
#' @keywords internal
my_function <- function(param1, param2) {
  # Implementation
}
```

**Rules:**
- Title: imperative verb + object (validate_row, coerce_value, load_mtcars_data)
- @description: one line, what does it do
- @details: additional nuances, side effects, constraints
- @param: include type and domain constraints
- @return: type and special values (NULL, invisible, etc.)
- @keywords internal: if not exported
- @examples: runnable, marked \dontrun if side effects

## Summary

Utility functions are designed as:
- **Single-responsibility**: One clear purpose
- **Composable**: Used in validation chains
- **Error-safe**: Rich error context, graceful degradation
- **Type-safe**: Reference schemas, validate coercions
- **Deterministic**: Pure functions where possible

Key principle: **Validation and coercion are separate, composable concerns.**
