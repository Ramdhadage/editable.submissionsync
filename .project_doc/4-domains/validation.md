# Validation Domain

## Overview

Validation in editable follows a **multi-phase, deterministic-first approach**:

1. **Deterministic checks** using `checkmate::assert_*()` (fail-fast)
2. **Risky operations** in `tryCatch()` blocks (database, type coercion)
3. **Rich error messaging** using `cli::cli_abort()` and `cli::cli_inform()`

The philosophy: **Validate early, validate often, provide rich context on failure.**

## Core Validation Pattern: update_cell()

The `update_cell()` method demonstrates the complete validation chain:

```r
update_cell = function(row, col, value) {
  # Phase 1: Data existence
  validate_data(self$data)
  
  # Phase 2: Row bounds
  validate_row(row, self$data)
  
  # Phase 3: Column resolution
  col_name <- validate_column(col, self$data)
  
  # Phase 4: Value constraints
  if (is.character(value) && identical(value, "")) {
    cli::cli_abort("Value cannot be empty for column '{col_name}'")
  }
  
  # Phase 5: Type compatibility check
  col_type <- class(self$original[[col_name]])[1]
  if (col_type %in% c("numeric", "integer")) {
    if (is.na(suppressWarnings(as.numeric(value)))) {
      cli::cli_abort("Invalid numeric value '{value}' for column '{col_name}'")
    }
  }
  
  # Phase 6: Type coercion (risky operation)
  coerced_value <- coerce_value(value, col_name, self$original)
  
  # Phase 7: NA detection (post-coercion)
  validate_no_na_loss(coerced_value, value, col_name)
  
  # Phase 8: Apply update (non-reversible)
  self$data[row, col_name] <- coerced_value
  private$modified_cells <- private$modified_cells + 1
  private$.summary_cache <- NULL
  
  invisible(TRUE)
}
```

**Key Pattern:**
- Validation happens BEFORE state mutation
- Each phase is independent and fails fast
- Failures include detailed context
- Only after ALL passes does update occur

## Phase 1: Data Existence

```r
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
```

**Used in:** `update_cell()`, `save()`, `summary()`

**Checks:**
- Data is not NULL
- Data is a data.frame
- No other structural requirements

## Phase 2: Row Bounds

```r
validate_row <- function(row, data) {
  tryCatch({
    checkmate::assert_integerish(row, len = 1, null.ok = FALSE)
    
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
```

**Ensures:**
- Integer-like index (1, 2, 3, ...)
- Within bounds (>= 1 and <= nrow)
- Provides range context in error

## Phase 3: Column Resolution

```r
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
```

**Supports:**
- Named column reference: `validate_column("mpg", data)` → `"mpg"`
- Index reference: `validate_column(1, data)` → `names(data)[1]`
- Returns normalized column name for subsequent phases

## Phase 4: Type Compatibility

```r
# In update_cell()
col_type <- class(self$original[[col_name]])[1]
if (col_type %in% c("numeric", "integer")) {
  if (is.na(suppressWarnings(as.numeric(value)))) {
    cli::cli_abort("Invalid numeric value '{value}' for column '{col_name}'")
  }
}
```

**Purpose:**
- Pre-flight check that value can be coerced to target type
- Prevents wasted effort on obviously invalid inputs
- Example: Reject `"not_a_number"` for numeric column immediately

## Phase 5: Type Coercion (Risky)

```r
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
```

**Key Features:**
- Uses `suppressWarnings()` to ignore coercion warnings during attempt
- Type determined from `self$original` (original schema)
- Wrapped in `tryCatch()` to catch coercion errors
- Rich error context if coercion fails

## Phase 6: NA Detection (Post-Coercion)

```r
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
```

**Purpose:**
- Prevents silent data loss via NA introduction
- Catches: `"invalid" → as.numeric() → NA`
- Allows valid transitions: `NA → NA` (no data loss)

## Summary Validation

```r
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
    summary_list
  }, error = function(e) {
    cli::cli_abort(c("Failed to generate summary", "x" = "{conditionMessage(e)}"))
  })
}
```

**Validates:**
- Data exists and is non-empty dataframe
- Columns are numeric (detect_numeric_columns handles errors gracefully)
- Means can be calculated without NA issues

## Save Validation Chain

Save operation has three levels of validation:

```r
save = function() {
  tryCatch({
    # Level 1: Connection validity
    validate_save_connection(self$con)
    
    # Level 2: Data validity
    validate_save_data(self$data)
    
    # Level 3: Structure consistency
    validate_save_structure(self$data, self$original)
    
    # Database operations (risky, in tryCatch)
    delete_mtcars_table(self$con)
    write_mtcars_to_db(self$con, self$data)
    
    # Success: update baseline
    self$original <- data.frame(self$data, check.names = FALSE)
    private$modified_cells <- 0
    
    cli::cli_inform("Data saved to DuckDB: {nrow(self$data)} rows saved successfully")
    invisible(self)
  }, error = function(e) {
    cli::cli_abort(c("Save operation failed", "x" = "{conditionMessage(e)}"))
  })
}
```

### Level 1: Connection Validity

```r
validate_save_connection <- function(con) {
  tryCatch({
    if (is.null(con)) stop("Connection is NULL")
    if (!inherits(con, "DBIConnection")) stop("Not a valid DBI connection object")
    if (!DBI::dbIsValid(con)) stop("Connection is not valid (closed or broken)")
  }, error = function(e) {
    cli::cli_abort(c("Invalid database connection for save", "x" = "{conditionMessage(e)}"))
  })
  invisible(NULL)
}
```

### Level 2: Data Validity

```r
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
```

### Level 3: Structure Consistency

```r
validate_save_structure <- function(data, original) {
  tryCatch({
    # Check column structure
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
    
    # Check row count
    current_rows <- nrow(data)
    original_rows <- nrow(original)
    if (current_rows != original_rows) {
      stop(sprintf("Row count mismatch: expected %d rows, found %d rows", original_rows, current_rows))
    }
    
    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "Data structure does not match original",
      "x" = "{conditionMessage(e)}",
      "i" = "Original: {nrow(original)} rows × {ncol(original)} columns",
      "i" = "Current: {nrow(data)} rows × {ncol(data)} columns"
    ))
  })
}
```

## Error Message Cleaning

UI displays need clean error messages:

```r
clean_error_message <- function(error_msg) {
  gsub("\u001b\\[[0-9;]*m", "", error_msg)
}
```

Used in mod_table.R:
```r
} catch (error) {
  error_msg <- conditionMessage(e)
  clean_msg <- clean_error_message(error_msg)
  awn::notify(
    paste("Update failed:", clean_error_message(error_msg)),
    type = "alert"
  )
}
```

## Key Validation Principles

1. **Fail-fast**: Deterministic checks before risky operations
2. **Rich context**: All errors include what, why, and how to resolve
3. **No silent failures**: Never silently coerce or introduce NA
4. **Separation of concerns**: Validation, type coercion, persistence are separate phases
5. **Type preservation**: Column types from original schema strictly maintained
6. **Transaction semantics**: Either fully succeed or fully fail, never partial updates

This validation architecture prevents data corruption and provides users with clear guidance on fixing issues.
