# Data Persistence Domain

## Overview

Data persistence in editable is built around **DuckDB with DBI**, providing:
- Embedded, file-based database (no external server required)
- Type-safe table I/O
- Transaction-like semantics (drop/create/write cycle)
- Bundled with application package

## Architecture: Embedded DuckDB

### Database Bundle Location

```r
validate_db_path <- function(package = "editable",
                             subdir = "extdata",
                             filename = "mtcars.duckdb") {
  tryCatch({
    db_path <- system.file(subdir, filename, package = package)
    checkmate::assert_file_exists(db_path, access = "r")
    db_path
  }, error = function(e) {
    cli::cli_abort(c(
      "DuckDB bundle file not found",
      "i" = "Package: {package}",
      "i" = "Expected location: {package}/inst/{extdata}/{filename}",
      "x" = "Error: {conditionMessage(e)}"
    ))
  })
}
```

**Key Points:**
- Database bundled at `inst/extdata/mtcars.duckdb`
- Located via `system.file()` during runtime
- Resolved at package install time

### Connection Lifecycle

**Initialization:**
```r
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

**Cleanup (Finalization):**
```r
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
```

**Key Points:**
- Opened in read-write mode by default (`read_only = FALSE`)
- `shutdown = TRUE` on disconnect ensures proper cleanup
- Finalizer called automatically on garbage collection

## Read Operations

### Load Data from Table

```r
load_mtcars_data <- function(con, table = "mtcars", default_rownames = NULL) {
  tryCatch({
    result <- DBI::dbReadTable(con, table)
    
    # Handle rownames if bundled database lacks a MODEL column
    if (is.null(rownames(result)) || all(rownames(result) == seq_len(nrow(result))) && !("MODEL" %in% names(result))) {
      if (!is.null(default_rownames) && length(default_rownames) == nrow(result)) {
        result <- cbind(MODEL = default_rownames, result, stringsAsFactors = FALSE)
      }
    }
    
    result <- set_mtcars_column_type(result)
    return(result)
  }, error = function(e) {
    cli::cli_warn(c(
      "Failed to load table from DuckDB, initializing with empty dataset",
      "i" = "Table: {table}",
      "x" = "Error: {conditionMessage(e)}"
    ))
    data.frame()
  })
}
```

**Features:**
- Uses `DBI::dbReadTable()` for automatic type preservation
- Handles missing rownames by inserting MODEL column
- Applies column type transformations (numeric, factor, logical)
- Graceful degradation: returns empty data.frame on failure

### Column Type Transformation

```r
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

**Purpose:**
- Applies domain-specific type conventions to loaded data
- Example: `am` (automatic) → logical, `cyl` (cylinders) → factor
- Ensures consistent types across load and save cycles

## Write Operations

### Transaction-Like Semantics

Save follows a DROP → CREATE → INSERT pattern (implicit in DBI.dbWriteTable):

```r
save = function() {
  tryCatch({
    validate_save_connection(self$con)
    validate_save_data(self$data)
    validate_save_structure(self$data, self$original)
    
    # Step 1: Delete existing table
    delete_mtcars_table(self$con)
    
    # Step 2: Write new table (creates it)
    write_mtcars_to_db(self$con, self$data)
    
    # Step 3: Update baseline to match new state
    self$original <- data.frame(self$data, check.names = FALSE)
    private$modified_cells <- 0
    
    cli::cli_inform("Data saved to DuckDB: {nrow(self$data)} rows saved successfully")
    invisible(self)
  }, error = function(e) {
    cli::cli_abort(c("Save operation failed", "x" = "{conditionMessage(e)}"))
  })
}
```

### Delete Existing Table

```r
delete_mtcars_table <- function(con) {
  tryCatch({
    DBI::dbExecute(con, "DROP TABLE IF EXISTS mtcars")
    invisible(NULL)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to delete existing mtcars table",
      "x" = "Database error: {conditionMessage(e)}"
    ))
  })
}
```

**Key Points:**
- Uses `DROP TABLE IF EXISTS` to avoid errors on first save
- Wrapped in tryCatch for database error handling

### Write Data to Table

```r
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
```

**Features:**
- `overwrite = TRUE` replaces entire table
- Error includes data shape context (rows, columns)
- Type coercion handled by DBI (respects column types from data)

## Data Flow: From DB to Store to UI and Back

### Initialization → Data Load
```
DataStore$new()
├─ validate_db_path()                      [Find bundled DB file]
├─ establish_duckdb_connection()           [Open read-write connection]
├─ load_mtcars_data(con, "mtcars")        [Query table from DB]
├─ set_mtcars_column_type()               [Apply type conventions]
└─ Store in: self$original, self$data     [Identical copies]
```

### Edit Cycle
```
User edits cell in table
│
├─ JavaScript: Shiny.setInputValue('_edit', {row, col, value})
│
├─ R: observeEvent(input$table_edit)      [Receive edit event]
│
├─ R: store$update_cell(row, col, value)  [Validate & update in-memory]
│
├─ R: store_trigger(...)                  [Force reactive invalidation]
│
└─ UI: reactive table re-renders from store$data
```

### Save Cycle
```
User clicks "Save Changes"
│
├─ UI: showModal(confirmation dialog)
│
├─ User clicks "Save to DuckDB"
│
├─ R: store$save()
│   ├─ validate_save_connection()
│   ├─ validate_save_data()
│   ├─ validate_save_structure()
│   ├─ delete_mtcars_table(con)
│   ├─ write_mtcars_to_db(con, data)
│   ├─ self$original = data.frame(self$data) [New baseline]
│   └─ private$modified_cells = 0
│
└─ UI: success notification, disable save/revert buttons
```

### Revert Cycle
```
User clicks "Revert Changes"
│
├─ R: store$revert()
│   ├─ data.frame(self$original) [Deep copy]
│   └─ self$data = reverted_data
│
├─ R: store_trigger(...)
│
└─ UI: reactive table re-renders from store$data (original baseline)
```

## Type Safety in Persistence

### Type Erasure Prevention

Column types from the original database schema are preserved across edits:

```r
coerce_value <- function(value, col_name, original_data) {
  tryCatch({
    # Reference type from original (DB schema)
    original_type <- class(original_data[[col_name]])[1]
    
    # Coerce to match
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
    cli::cli_abort(...)
  })
}
```

**Key Points:**
- Type reference always comes from `self$original` (DB schema)
- Coercion attempts to match original type
- Failure prevents update (validation failure, not silent coercion)
- Write-back uses DBI::dbWriteTable() which respects R types

### Example: Numeric Column

```
DB: mtcars.mpg (numeric)
│
Load: self$original$mpg = numeric vector
      self$data$mpg = numeric vector
│
Edit: User enters "22.5"
      validate_column("mpg") → "mpg"
      coerce_value("22.5", "mpg", original_data)
        original_type = "numeric"
        as.numeric("22.5") → 22.5 [numeric]
│
Save: write_mtcars_to_db(con, data)
      DBI::dbWriteTable() preserves numeric type
      DB: mtcars.mpg (numeric) ← 22.5
```

## Caching and Performance

### Summary Cache

```r
summary = function() {
  tryCatch({
    # Use cache if available and no modifications
    if (!is.null(private$.summary_cache) && private$modified_cells == 0) {
      return(private$.summary_cache)
    }
    
    # ... compute summary ...
    
    private$.summary_cache <<- summary_list
    summary_list
  }, error = function(e) {
    cli::cli_abort(...)
  })
}
```

**Optimization:**
- Summary cached until next modification
- Cache invalidated on every `update_cell()` or `revert()`
- Avoids recomputing means and counts on every reactive trigger

## Constraints & Limitations

1. **Single Table Focus**: Currently only `mtcars` table. Multi-table datasets would require schema changes.
2. **File-Based Locking**: DuckDB file locks prevent concurrent access without external mutex.
3. **No Transactions**: Drop/create cycle isn't a true transaction. Interrupted save could leave table missing.
4. **Type Limitations**: Only handles basic types (numeric, integer, character, logical, factor).
5. **Schema Rigidity**: Row count must match original. Cannot add/delete rows (only cells).

## Summary

The data persistence layer treats the database as a **reliable source of truth** while keeping **in-memory edits isolated** until explicitly saved. This architecture provides:
- **Safety**: Type preservation, structure validation, rollback capability
- **Simplicity**: Embedded database, no external dependencies
- **Clarity**: Explicit save/revert cycles, no implicit persistence

Key principle: **Database is the source of truth; R6 DataStore is the working copy.**
