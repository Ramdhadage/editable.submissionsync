# R6 Classes Style Guide

## Overview

R6 classes in editable implement sophisticated state management with emphasis on data integrity, type safety, and comprehensive validation. The DataStore class is the canonical example.

## File Convention

**File Pattern**: `R/DataStore.R` (one R6 class per file, named after class)

## Class Structure

### Basic Template

```r
#' Class Name (CamelCase)
#'
#' @description
#' Roxygen documentation block explaining the class purpose and usage.
#'
#' @section Usage:
#' ```r
#' obj <- ClassName$new()
#' obj$method()
#' ```
#'
#' @export
ClassName <- R6::R6Class(
  "ClassName",
  
  public = list(
    # PUBLIC FIELDS
    field1 = NULL,
    field2 = NULL,
    
    # INITIALIZATION
    initialize = function(param1 = NULL) {
      # Constructor logic
      invisible(self)
    },
    
    # PUBLIC METHODS (business logic)
    method1 = function(arg1) {
      # Implementation
    },
    
    method2 = function(arg1, arg2) {
      # Implementation
    }
  ),
  
  private = list(
    # PRIVATE FIELDS
    internal_field = NULL,
    
    # PRIVATE METHODS
    helper_method = function() {
      # Helper logic
    },
    
    # FINALIZER (cleanup)
    finalize = function() {
      # Resource cleanup
    }
  )
)
```

## Field Conventions

### Public Fields

```r
public = list(
  #' @field con DBI connection object
  con = NULL,
  
  #' @field data Working data frame
  data = NULL,
  
  #' @field original Immutable baseline data
  original = NULL
)
```

**Rules:**
- One `@field` documentation per public field
- Include type information in documentation
- Initialize to NULL (explicitly set in initialize())
- Document purpose and constraints

### Private Fields

```r
private = list(
  #' @field db_path Path to bundled database file
  db_path = NULL,
  
  #' @field modified_cells Counter for tracking edits
  modified_cells = 0,
  
  #' @field .summary_cache Cached summary (invalidated on changes)
  .summary_cache = NULL
)
```

**Rules:**
- Private fields start with underscore if caching or internal state
- Document purpose even though not exported
- Include constraints (e.g., "monotonic counter", "invalidated on change")

## Initialization (Initialize Method)

### Structure

```r
initialize = function() {
  tryCatch({
    # Phase 1: Validation of inputs
    # Phase 2: Resource initialization
    # Phase 3: Data loading
    # Phase 4: State setup
    
    cli::cli_inform("Class initialized successfully")
  }, error = function(e) {
    # Cleanup on failure
    if (!is.null(self$con)) {
      tryCatch({
        # Resource cleanup
      }, error = function(x) NULL)
    }
    
    cli::cli_abort(c(
      "Initialization failed",
      "x" = "{conditionMessage(e)}"
    ))
  })
  
  invisible(self)  # Enable method chaining
}
```

**Rules:**
- Wrap entire initialization in `tryCatch`
- Clean up partial state on failure
- End with `invisible(self)` for method chaining
- Use `cli::cli_inform()` and `cli::cli_abort()` for messages
- Document each phase with comments

## Public Method Conventions

### Data Mutation Methods

```r
#' Update Cell Value
#'
#' @description
#' Type-safe cell update with full validation chain.
#'
#' @param row Integer row index (1-based)
#' @param col Column name or index
#' @param value New value to assign
#'
#' @return Invisible TRUE on success, throws cli_abort on failure
#' @examples
#' \dontrun{
#' store$update_cell(1, "mpg", 22.5)
#' }
update_cell = function(row, col, value) {
  # Phase 1: Data existence
  validate_data(self$data)
  
  # Phase 2: Row bounds
  validate_row(row, self$data)
  
  # Phase 3: Column resolution
  col_name <- validate_column(col, self$data)
  
  # Phases continue...
  
  # MUTATION: Only after all validation passes
  self$data[row, col_name] <- coerced_value
  private$modified_cells <- private$modified_cells + 1
  private$.summary_cache <- NULL  # Invalidate cache
  
  invisible(TRUE)
}
```

**Rules:**
- All mutations guarded by validation functions
- Validate BEFORE mutating state
- Use `invisible(TRUE)` for no-value returns
- Include roxygen examples (marked \dontrun if interactive)
- Document parameters, return value, and side effects

### Getter Methods

```r
#' Get Modified Cells Count
#'
#' @description
#' Returns number of cells modified since last save or revert.
#'
#' @return Integer count
get_modified_count = function() {
  private$modified_cells
}
```

**Rules:**
- Simple, single-line getters for private fields
- Always documented with roxygen
- Return types specified in @return

### Query Methods

```r
#' Generate Dataset Summary
#'
#' @description
#' Computes row count, column count, and numeric means.
#' Results cached until next modification.
#'
#' @return List with fields: message, rows, cols, numeric_means
summary = function() {
  tryCatch({
    # Cache check
    if (!is.null(private$.summary_cache) && private$modified_cells == 0) {
      return(private$.summary_cache)
    }
    
    # Validation
    validate_summary_data(self$data)
    
    # Computation
    numeric_cols <- detect_numeric_columns(self$data)
    numeric_means <- if (length(numeric_cols) > 0) {
      calculate_column_means(self$data, numeric_cols)
    } else {
      NULL
    }
    
    # Result construction
    summary_list <- list(
      message = sprintf("Rows: %d | Columns: %d", nrow(self$data), ncol(self$data)),
      rows = nrow(self$data),
      cols = ncol(self$data),
      numeric_means = numeric_means
    )
    
    # Cache and return
    private$.summary_cache <<- summary_list
    summary_list
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to generate summary",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
```

**Rules:**
- Implement caching with cache invalidation on mutation
- Use `<<-` for cache assignment (parent environment)
- Return structured list with named fields
- Document cache behavior in roxygen
- Wrap in tryCatch with rich error messages

### State Mutation with Side Effects

```r
#' Save Current Data to Database
#'
#' @description
#' Persists working data back to DuckDB.
#' Updates self$original to match saved state (new baseline).
#' Resets modification counter.
#'
#' @return Invisible self for method chaining
save = function() {
  tryCatch({
    # Multi-phase validation
    validate_save_connection(self$con)
    validate_save_data(self$data)
    validate_save_structure(self$data, self$original)
    
    # Database operations
    delete_mtcars_table(self$con)
    write_mtcars_to_db(self$con, self$data)
    
    # State updates
    self$original <- data.frame(self$data, check.names = FALSE)
    private$modified_cells <- 0
    
    # Messaging
    cli::cli_inform("Data saved to DuckDB: {nrow(self$data)} rows saved successfully")
    
    # Method chaining
    invisible(self)
  }, error = function(e) {
    cli::cli_abort(c(
      "Save operation failed",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
```

**Rules:**
- Use `invisible(self)` for method chaining
- Update baseline after successful save
- Reset derived state (counters, caches)
- Document all side effects in roxygen
- Use cli messaging for success/failure

## Finalization (Cleanup)

```r
private = list(
  #' Cleanup: Close DuckDB Connection
  #'
  #' @description
  #' Finalizer automatically called on garbage collection.
  #' Ensures proper resource cleanup.
  #'
  #' @return Invisible NULL
  finalize = function() {
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
```

**Rules:**
- Implement finalize() for resource cleanup
- Never fatal error in finalize (use cli::cli_warn only)
- Document it even though it's private
- Always close connections, files, etc. gracefully

## Error Handling in R6 Methods

### Pattern: Validation + Risky Operations

```r
public_method = function(arg) {
  # Deterministic validation (checkmate)
  tryCatch({
    checkmate::assert_integerish(arg, len = 1)
  }, error = function(e) {
    cli::cli_abort(c(
      "Invalid argument",
      "x" = "{conditionMessage(e)}"
    ))
  })
  
  # Risky operations (DB, type coercion, etc.)
  result <- tryCatch({
    risky_operation(self$data, arg)
  }, error = function(e) {
    cli::cli_abort(c(
      "Operation failed",
      "i" = "Context information",
      "x" = "{conditionMessage(e)}"
    ))
  })
  
  result
}
```

**Rules:**
- Deterministic checks first (fail-fast)
- Risky operations after validation
- Separate error handling for each phase
- Include context in error messages

## Type Safety

### Type Preservation Pattern

```r
# Always reference original types when coercing user input
original_type <- class(self$original[[col_name]])[1]

coerced <- switch(original_type,
  "numeric" = as.numeric(value),
  "integer" = as.integer(value),
  "character" = as.character(value),
  "logical" = as.logical(value),
  "factor" = factor(value, levels = levels(self$original[[col_name]])),
  as(value, original_type)
)
```

**Rules:**
- Never infer types from user input
- Always reference original schema for type
- Use switch for type-specific handling
- Preserve factor levels when coercing

## Documentation

### Roxygen Template

```r
#' Class Name (Title Case)
#'
#' @description
#' Detailed explanation of class purpose, when to use it, and key patterns.
#' Include architecture notes if relevant.
#'
#' @details
#' Implementation details, design decisions, constraints.
#'
#' @section Fields:
#' \describe{
#'   \item{field1}{Description}
#'   \item{field2}{Description}
#' }
#'
#' @section Methods:
#' \describe{
#'   \item{initialize()}{Constructor}
#'   \item{method()}{Method description}
#' }
#'
#' @section Usage:
#' ```r
#' obj <- ClassName$new()
#' obj$method(arg)
#' obj$another_method()
#' ```
#'
#' @export
```

**Rules:**
- Title: concise, class name
- @description: when and why to use
- @details: how it works internally
- @section Fields: public fields documented
- @section Methods: key methods explained
- @section Usage: runnable example
- @export: if public; omit if private

## Inheritance Pattern (if needed)

```r
ChildClass <- R6::R6Class(
  "ChildClass",
  inherit = ParentClass,
  public = list(
    # Override or extend methods
    method_override = function() {
      super$method_override()  # Call parent
      # Additional logic
    }
  )
)
```

**Rules:**
- Use `inherit = ParentClass` in R6::R6Class
- Use `super$method()` to call parent methods
- Document which methods are overridden

## Summary

DataStore-style R6 classes prioritize:
- **Safety**: Multi-phase validation before mutations
- **Clarity**: Explicit public methods with clear contracts
- **Maintainability**: Rich documentation and error messages
- **Chainability**: Return `invisible(self)` where appropriate
- **Robustness**: Comprehensive error handling and cleanup

Key principle: **R6 classes encapsulate complex, stateful behavior with clear public interfaces and exhaustive validation.**
