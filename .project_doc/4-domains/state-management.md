# State Management Domain

## Overview

State management in editable is built entirely on **R6 classes** paired with **Shiny reactive values**. The architecture emphasizes:
- Single source of truth (DataStore R6 object)
- Immutable snapshots for data integrity
- Explicit reactive triggers for controlled invalidation
- Clear separation between data and computation

## Core Pattern: R6-Based DataStore

All application state lives in a single DataStore R6 object, initialized once and passed to modules via reactiveVal.

### Initialization

From `R/DataStore.R`:

```r
DataStore <- R6::R6Class(
  "DataStore",
  public = list(
    con = NULL,
    data = NULL,
    original = NULL,
    
    initialize = function() {
      tryCatch({
        private$db_path <- validate_db_path()
        self$con <- establish_duckdb_connection(private$db_path, read_only = FALSE)
        
        query_result <- load_mtcars_data(self$con, table = "mtcars", default_rownames = new_rownames)
        self$original <- data.frame(query_result, check.names = TRUE)
        self$data <- data.frame(query_result, check.names = TRUE)
        private$modified_cells <- 0
        
        cli::cli_inform("DataStore initialized: {nrow(self$data)} rows loaded from DuckDB")
      }, error = function(e) {
        if (!is.null(self$con)) {
          tryCatch({ DBI::dbDisconnect(self$con, shutdown = TRUE) }, error = function(x) NULL)
        }
        cli::cli_abort(c("DataStore initialization failed", "x" = "{conditionMessage(e)}"))
      })
      invisible(self)
    }
  )
)
```

**Key Points:**
- `self$original` stores the immutable baseline (loaded from DB)
- `self$data` is the working, mutable copy
- Both initialized to identical data.frame
- `self$con` holds the active database connection

### Usage in app_server.R

```r
app_server <- function(input, output, session) {
  store <- get_cached_store()
  store_reactive <- reactiveVal(store)          # Wrap R6 in reactiveVal
  store_trigger <- reactiveVal(0)               # Manual trigger for invalidation
  mod_table_server("table", store_reactive, store_trigger)
}
```

**Key Points:**
- R6 object wrapped in `reactiveVal()` for explicit Shiny integration
- `store_trigger` is a separate reactive value used to force invalidation
- Both passed to module for state access and updates

## Immutable Snapshot Pattern

The immutable snapshot pattern ensures data integrity:

### Original (Immutable)
```r
self$original <- data.frame(query_result, check.names = TRUE)
```

Used only for:
- Reverting to baseline state
- Type reference for cell validation
- Providing audit baseline

### Data (Mutable)
```r
self$data <- data.frame(query_result, check.names = TRUE)
```

Used for:
- User-visible table display
- Edit targets
- Save operations

### Revert Pattern (Deep Copy)

```r
revert = function() {
  tryCatch({
    checkmate::assert_data_frame(self$original, null.ok = FALSE)
    
    reverted_data <- tryCatch({
      data.frame(self$original, check.names = FALSE)  # Deep copy via data.frame()
    }, error = function(e) {
      cli::cli_abort(c("Failed to revert data", "x" = "Error during deep copy: {conditionMessage(e)}"))
    })
    
    self$data <- reverted_data
    private$modified_cells <- 0
    private$.summary_cache <- NULL
    
    cli::cli_inform("Data reverted to original state ({nrow(self$data)} rows)")
    invisible(self)
  }, error = function(e) {
    cli::cli_abort(c("Revert operation failed", "x" = "{conditionMessage(e)}"))
  })
}
```

**Critical Detail:** `data.frame(self$original, check.names = FALSE)` creates a **deep copy**, not a reference. This prevents unintended modifications to the original.

## Reactive Integration in Modules

From `R/mod_table.R`:

```r
mod_table_server <- function(id, store_reactive, store_trigger) {
  shiny::moduleServer(id, function(input, output, session) {
    
    # Reactive expression that depends on store_trigger
    table_data <- shiny::reactive({
      store_trigger()  # Explicit dependency
      store <- store_reactive()  # Read the R6 object
      
      if (is.null(store$data)) {
        return(data.frame())
      }
      store$data
    })
    
    # Render table whenever table_data changes
    output$table <- renderHotwidget({
      data <- table_data()
      if (nrow(data) == 0) {
        return(hotwidget(data = data.frame(Message = "No data loaded")))
      }
      hotwidget(data = data)
    })
  })
}
```

**Key Points:**
- `table_data()` reactive depends on `store_trigger()` explicitly
- Reading `store_reactive()` inside the reactive accesses the current R6 object
- No implicit dataframe reactivity; all updates explicit

## Cell Update Flow

When a user edits a cell:

1. **JavaScript sends edit event:**
   ```javascript
   Shiny.setInputValue(el.id + '_edit', {
     row: 0,
     col: "mpg",
     oldValue: 21.0,
     value: 22.5
   });
   ```

2. **R receives and queues edit:**
   ```r
   shiny::observeEvent(input$table_edit, {
     edit <- input$table_edit
     edit_batch(edit)  # Queue in reactiveVal
     
     # Schedule processing via RAF
     raf_code <- "..."
     raf_id <- shinyjs::runjs(raf_code)
     edit_timer(raf_id)
   })
   ```

3. **RAF callback triggers processing:**
   ```r
   shiny::observeEvent(input$`_raf_trigger`, {
     edit <- edit_batch()
     
     tryCatch({
       r_row <- edit$row + 1  # Convert 0-based to 1-based
       
       store_reactive()$update_cell(
         row = r_row,
         col = edit$col,
         value = edit$value
       )
       
       store_trigger(store_trigger() + 1)  # Force invalidation
       shinyjs::enable("save")
       shinyjs::enable("revert")
       
     }, error = function(e) {
       awn::notify(paste("Update failed:", clean_error_message(error_msg)), type = "alert")
       store_trigger(store_trigger() + 1)  # Redraw to show rollback
     })
   })
   ```

**Key Points:**
- Manual RAF debouncing prevents edit storms
- R6 method called with converted indices
- Explicit trigger increment forces all dependents to recompute
- Errors trigger UI redraw to show rollback

## Save & New Baseline

Save operation updates `self$original` to become the new baseline:

```r
save = function() {
  tryCatch({
    validate_save_connection(self$con)
    validate_save_data(self$data)
    validate_save_structure(self$data, self$original)
    
    delete_mtcars_table(self$con)
    write_mtcars_to_db(self$con, self$data)
    
    # Update original to match current state
    self$original <- data.frame(self$data, check.names = FALSE)
    
    private$modified_cells <- 0
    cli::cli_inform("Data saved to DuckDB: {nrow(self$data)} rows saved successfully")
    invisible(self)
  }, error = function(e) {
    cli::cli_abort(c("Save operation failed", "x" = "{conditionMessage(e)}"))
  })
}
```

**Key Points:**
- Success requires: connection valid, data non-empty, structure matches original
- Table dropped and recreated (transactional semantics)
- `self$original` updated to match saved state (new baseline)
- Modified counter reset to 0
- Subsequent reverts go to this new baseline

## Modification Tracking

```r
update_cell = function(row, col, value) {
  # ... validation ...
  
  self$data[row, col_name] <- coerced_value
  private$modified_cells <- private$modified_cells + 1
  private$.summary_cache <- NULL  # Invalidate cache
  
  invisible(TRUE)
}

get_modified_count = function() {
  private$modified_cells
}
```

**Key Points:**
- Every update increments counter
- Revert and save reset counter
- Counter drives UI state (enable/disable save/revert buttons)

## Summary

The state management architecture uses a purposeful combination of R6 (for complex state logic) and Shiny reactives (for UI integration). This approach provides:
- **Clarity**: Single, authoritative DataStore object
- **Control**: Explicit trigger management, no magic dependencies
- **Integrity**: Immutable snapshots, deep copies, transaction-like semantics
- **Auditability**: Modification tracking, change logging capacity

Key design principle: **R6 handles business logic and validation; Shiny handles UI reactivity and event wiring.**
