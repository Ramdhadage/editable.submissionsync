# Copilot Instructions: editable

**Version:** 1.0.0  
**Project:** editable — Interactive Excel-Style Data Editor
**Technology Stack:** R + Shiny + DuckDB + Custom HTMLWidgets  
**Last Updated:** 2024  

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture & Domains](#architecture--domains)
3. [File Category Reference](#file-category-reference)
4. [Feature Scaffold Guide](#feature-scaffold-guide)
5. [Integration Rules](#integration-rules)
6. [Code Patterns Reference](#code-patterns-reference)
7. [Example Prompt Usage](#example-prompt-usage)

---

## Project Overview

### Vision

Transform clinical trial data management from spreadsheet-based workflows into a secure, validated, browser-based application targeting pharmaceutical companies.

**Target Users:** Clinical data managers, trial coordinators, regulatory compliance specialists  
**Primary Problem:** Error-prone manual data entry with no audit trail or validation  
**Solution:** Interactive table editor with real-time validation, immutable change tracking, and DuckDB persistence  

### Technology Choices

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| **Web Framework** | Shiny | Browser-based, R-native, no JavaScript required |
| **State Management** | R6 Classes | Explicit mutability, encapsulation, validation |
| **Data Persistence** | DuckDB | Embedded database (no server), ACID compliance, SQL querying |
| **Table Editing** | Handsontable | Excel-like UX, column filters, sorting, pagination |
| **UI Framework** | Bootstrap 5 + bslib | Responsive, enterprise-grade styling, accessibility |
| **Custom Widgets** | htmlwidgets | R↔JavaScript bridge, Handsontable integration |
| **Testing** | testthat + shinytest2 | R-native unit tests, reactive testing |

### Core Features

- ✅ **Single-dataset editing** (currently: mtcars, extensible to multi-dataset)
- ✅ **Real-time type validation** (numeric, integer, logical, text, factor)
- ✅ **Immutable change tracking** (original baseline, current state separately maintained)
- ✅ **Save/revert semantics** (transaction-like operations)
- ✅ **DuckDB persistence** (automatic save, no manual serialization)
- ✅ **Handsontable integration** (column filters, sorting, pagination)
- ✅ **Comprehensive validation** (deterministic checks before risky operations)

### Production-Ready Status

| Dimension | Status | Notes |
|-----------|--------|-------|
| **Code Quality** | 90% | Validation chains, error handling, R6 patterns all robust |
| **Testing** | 80% | 60+ unit tests; needs integration tests for UI flows |
| **Documentation** | 60% | Code comments present; needs user guide + deployment docs |
| **Security** | 20% | No authentication, no audit logging, no encryption (future) |
| **Scalability** | 70% | Single dataset; multi-dataset requires UI refactor |
| **Performance** | 85% | RAF debouncing, reactive efficiency, caching in place |

### Pre-Production Gaps Requiring Implementation

1. **Authentication & Authorization** — User login, role-based access
2. **Audit Logging** — Change history with timestamps, user attribution
3. **Encryption** — At-rest (DuckDB) and in-transit (HTTPS)
4. **Multi-dataset Support** — Dataset selection, switching
5. **Data Import/Export** — CSV, Excel, regulatory format support
6. **Compliance Documentation** — Risk assessment, SOPs, validation reports
7. **CI/CD Pipeline** — Automated testing, Docker deployment
8. **Monitoring & Logging** — Error tracking, usage analytics

---

## Architecture & Domains

The application is organized into **7 architectural domains**, each with specific patterns and constraints:

### 1. State Management (R6 DataStore)

**Responsibility:** Single source of truth for application state  
**Key Class:** `DataStore` (R/DataStore.R, 450+ lines)  
**Pattern:** Immutable snapshot + mutable current state

#### Core Workflow

```
User edits cell
    ↓
JavaScript Handsontable captures afterChange event
    ↓
RAF debouncing batches edits (300ms window)
    ↓
Shiny input binding sends batch to server
    ↓
DataStore$update_cell() validates in 6 phases
    ↓
Phase 1: Deterministic checks (type, bounds)
Phase 2: Coerce value to correct type
Phase 3: Check for silent data loss
Phase 4: Serialize change
Phase 5: Update internal state
Phase 6: Trigger dependent reactives
    ↓
UI re-renders with new data
    ↓
User clicks save
    ↓
DataStore$save() writes to DuckDB, updates baseline
```

#### Key Constraints

- **Immutability:** `self$original` is read-only snapshot of baseline
- **One-version-at-a-time:** Cannot have unsaved edits + save simultaneously
- **Type safety:** All values coerced to original column types
- **Transaction semantics:** save() or revert(), never partial updates
- **Modification tracking:** `self$modification_counter` for reactive dependencies

#### Methods

- `update_cell(row, col, value)` — Validates and updates single cell
- `save()` — Persists to DuckDB, updates baseline
- `revert()` — Discards changes, reverts to baseline
- `summary()` — Returns display summary (types, means, row count)
- `get_modified_count()` — Number of cells changed (for UI feedback)

### 2. Validation (Multi-Phase Chain)

**Responsibility:** Type-safe, error-rich validation with deterministic-first approach  
**Location:** R/DataStore.R (update_cell) + R/utils.R (validation functions)  
**Pattern:** Compose validators with explicit phase separation

#### Validation Phases

```
Phase 1: DETERMINISTIC CHECKS
├─ Is row in bounds? [1, nrow(data)]
├─ Is column in bounds? [1, ncol(data)]
├─ Is value not NULL/empty string combo?
└─ Is value valid for target column type?

Phase 2: TYPE COERCION
├─ Coerce value to original column type
└─ Suppress NA warnings (expected behavior)

Phase 3: DATA LOSS DETECTION
├─ Did coercion produce unexpected NA? (value → NA)
└─ Is NA → NA transition OK? (user explicitly entering NA)

Phase 4: SERIALIZE (optional, logging)
├─ Record change in modification log
└─ Timestamp + source (user edit vs. revert)

Phase 5: UPDATE STATE
├─ Set self$data[row, col] ← coerced_value
├─ Increment modification counter
└─ Mark row as modified

Phase 6: TRIGGER REACTIVES
└─ store_trigger$increment() → invalidates all dependent outputs
```

#### Error Handling Pattern

```r
tryCatch(
  # Phase 1: Deterministic checks (fast, no side effects)
  {
    validate_row(row, data)
    validate_column(col, data)
    value
  },
  # Phase 2: Type coercion (may fail, but reversible)
  error = function(e1) {
    tryCatch({
      coerced <- coerce_value(value, col, data)
      validate_no_na_loss(coerced, value, col)
      coerced
    }, error = function(e2) {
      cli::cli_abort(c(
        "Validation failed",
        "i" = "Row {row}, Column {col}",
        "x" = "{conditionMessage(e2)}"
      ))
    })
  }
)
```

#### Validation Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `validate_row()` | Check bounds [1, nrow] | `validate_row(5, mtcars)` |
| `validate_column()` | Accept name or index | `validate_column("mpg", mtcars)` |
| `coerce_value()` | Type-safe conversion | `coerce_value("3.14", "numeric", mtcars)` |
| `validate_no_na_loss()` | Detect data loss | `validate_no_na_loss(NA, "3.14", "cyl")` |
| `detect_numeric_columns()` | Find numeric cols | `detect_numeric_columns(mtcars)` |

### 3. Data Persistence (DuckDB Integration)

**Responsibility:** Read/write operations with ACID guarantees  
**Location:** R/utils.R (load_* and write_* functions) + R/DataStore.R (save())  
**Pattern:** DBI interface with type preservation

#### Lifecycle

```
Application Startup
├─ establish_duckdb_connection() → creates DBI connection
├─ load_mtcars_data() → reads table from database
├─ apply type conversions (set_mtcars_column_type)
└─ initialize DataStore with baseline data

User Edits & Saves
├─ Edit cells in memory (self$data)
├─ Click save button
├─ DataStore$save() executes:
│  ├─ DELETE FROM mtcars (replaces old data)
│  ├─ INSERT INTO mtcars (writes new rows)
│  └─ UPDATE self$original ← self$data (update baseline)
└─ UI confirmation notification

Session End
└─ DBI connection auto-closes (garbage collection)
```

#### Type Preservation

| R Type | DuckDB Type | Handsontable Rendering |
|--------|------------|----------------------|
| numeric | DOUBLE | Numeric input, formatting |
| integer | INTEGER | Numeric input (no decimals) |
| character | VARCHAR | Text input |
| logical | BOOLEAN | Checkbox |
| factor | VARCHAR | Text (levels stored as metadata) |

#### Write Pattern

```r
#' Write data frame to DuckDB table (replace mode)
write_mtcars_to_db <- function(con, data, table_name = "mtcars") {
  tryCatch({
    # Step 1: Validate structure
    validate_data(data, table_name)
    
    # Step 2: Clear old table
    DBI::dbExecute(con, sprintf("DELETE FROM %s", table_name))
    
    # Step 3: Write new data
    DBI::dbWriteTable(con, table_name, data, append = TRUE, row.names = FALSE)
    
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Write to DuckDB failed",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
```

### 4. UI Components (Shiny Modules)

**Responsibility:** Namespace-isolated, reusable UI + reactive logic  
**Location:** R/mod_table.R (module definition) + R/app_ui.R (main layout)  
**Pattern:** Shiny module conventions with explicit namespace isolation

#### Module Structure

```
mod_table_ui (id)
├─ Create namespace
├─ Heading
├─ Control buttons (save, revert, export)
├─ Summary metrics (row count, modified count, column types)
├─ hotwidget_output("table") — render Handsontable
└─ Return tagList (no page wrapper)

mod_table_server (id, con)
├─ Initialize DataStore with DuckDB data
├─ Create reactive expressions:
│  ├─ store_reactive() → reactive(store$data)
│  └─ store_trigger() → reactiveVal for invalidation
├─ Register event handlers:
│  ├─ observeEvent(input$table_edits) → batch edit processing
│  ├─ observeEvent(input$save_btn) → modal confirmation
│  ├─ observeEvent(input$revert_btn) → reset to baseline
│  └─ observeEvent(input$export_btn) → future: CSV export
├─ Create renderers:
│  ├─ output$app_summary → summary HTML
│  └─ output$table → hotwidget rendering
└─ Return reactive store for parent access (if needed)
```

#### Event Handler Pattern

```r
# Simple action (revert)
observeEvent(input$revert_btn, {
  tryCatch({
    store$revert()  # R6 revert method
    store_trigger$increment()  # Trigger re-render
    awn::awn("success", "Changes reverted")  # Notification
  }, error = function(e) {
    awn::awn("error", clean_error_message(conditionMessage(e)))
  })
})

# Complex action with modal (save)
observeEvent(input$save_btn, {
  showModal(modalDialog(
    title = "Confirm Save",
    "Are you sure you want to save changes to database?",
    footer = tagList(
      actionButton(ns("save_confirm"), "Yes, save", class = "btn-danger"),
      modalButton("Cancel")
    )
  ))
})

observeEvent(input$save_confirm, {
  tryCatch({
    store$save()  # Writes to DuckDB
    store_trigger$increment()  # Re-render
    removeModal()
    awn::awn("success", "Data saved to database")
  }, error = function(e) {
    awn::awn("error", clean_error_message(conditionMessage(e)))
  })
})
```

#### RAF Debouncing for Edits

JavaScript batches edits, R server processes:

```r
observeEvent(input$table_edits, {
  tryCatch({
    edits <- input$table_edits  # Batch of changes
    
    for (edit in edits) {
      store$update_cell(
        row = edit$row,
        col = edit$col,
        value = edit$value
      )
    }
    
    store_trigger$increment()  # Single re-render for batch
    awn::awn("info", "Edits applied: {length(edits)} cells")
  }, error = function(e) {
    awn::awn("error", clean_error_message(conditionMessage(e)))
  })
})
```

### 5. HTMLWidget Communication (Handsontable)

**Responsibility:** Bidirectional R ↔ JavaScript communication for table editing  
**Location:** R/hotwidget.R (R wrapper) + inst/htmlwidgets/hotwidget.js (factory + event hooks)  
**Pattern:** Shiny input binding with RAF debouncing

#### Communication Flow

```
User edits cell in browser
    ↓
Handsontable.afterChange hook fires (JS)
    ↓
collectEdits() batches changes, schedules RAF
    ↓
requestAnimationFrame fires (device-refreshed timing)
    ↓
Shiny.setInputValue("hotwidget_edits", batch)
    ↓
observeEvent(input$table_edits) receives batch
    ↓
Server processes all edits at once
    ↓
store_trigger$increment()
    ↓
Shiny invalidates hotwidget output
    ↓
renderValue(x) receives updated x$data
    ↓
Handsontable.updateSettings({data: x$data})
    ↓
Browser re-renders table with new data
```

#### R Wrapper (hotwidget.R)

```r
hotwidget <- function(
    data,
    colTypes = NULL,
    rowHeaders = TRUE,
    colHeaders = TRUE,
    ...) {
  
  # Input validation
  checkmate::assert_data_frame(data, null.ok = FALSE)
  
  # Auto-detect types
  if (is.null(colTypes)) {
    colTypes <- detect_column_types(data)
  }
  
  # Create parameters list
  x <- list(
    data = data,
    colTypes = colTypes,
    rowHeaders = rowHeaders,
    colHeaders = colHeaders,
    pagination = list(enabled = TRUE, pageSize = 50),
    filters = TRUE,
    columnSorting = list(indicator = TRUE)
  )
  
  # Return htmlwidget
  htmlwidgets::createWidget(
    name = "hotwidget",
    x = x,
    package = "editable",
    ...
  )
}
```

#### JavaScript Factory (hotwidget.js)

```javascript
HTMLWidgets.widget({
  name: "hotwidget",
  type: "output",
  
  factory: function(el, width, height) {
    var instance = {
      edits: {},
      editScheduled: false,
      hot: null
    };
    
    return {
      renderValue: function(x) {
        if (instance.hot) instance.hot.destroy();
        
        instance.hot = new Handsontable(el, {
          data: x.data,
          colHeaders: x.colHeaders,
          rowHeaders: x.rowHeaders,
          colTypes: x.colTypes,
          afterChange: function(changes, source) {
            if (source === 'loadData') return;  // Ignore initial load
            
            // Batch changes
            changes.forEach(function(change) {
              instance.edits[change[0] + '_' + change[1]] = {
                row: change[0] + 1,  // 0-based → 1-based
                col: change[1] + 1,
                value: change[3]
              };
            });
            
            // Schedule RAF
            if (!instance.editScheduled) {
              instance.editScheduled = true;
              requestAnimationFrame(function() {
                var batch = Object.values(instance.edits);
                if (batch.length > 0) {
                  Shiny.setInputValue("hotwidget_edits", batch);
                }
                instance.edits = {};
                instance.editScheduled = false;
              });
            }
          }
        });
      },
      
      resize: function(w, h) {
        if (instance.hot) {
          instance.hot.updateSettings({height: h});
        }
      }
    };
  }
});
```

**Key Pattern:** Index conversion 0-based (JavaScript) ↔ 1-based (R)

### 6. Testing (Unit + Integration)

**Responsibility:** Validate all domains with fast feedback  
**Location:** tests/testthat/ (60+ tests)  
**Pattern:** Arrange-Act-Assert with real DuckDB integration (not mocked)

#### Test Organization

```
test-DataStore.R (450+ lines)
├─ Initialization (4 tests)
│  ├─ Fresh instance creates empty data
│  ├─ Loads initial data correctly
│  ├─ Preserves types on load
│  └─ Maintains immutable original
│
├─ Cell Updates (8 tests)
│  ├─ Updates numeric column correctly
│  ├─ Coerces string to numeric
│  ├─ Rejects invalid numeric
│  ├─ Clamps integer bounds
│  ├─ Updates logical (checkbox)
│  ├─ Updates factors (with level validation)
│  └─ Updates text (no type coercion)
│
├─ Revert Operations (10+ tests)
│  ├─ Revert single cell discards change
│  ├─ Revert all discards all changes
│  ├─ Revert updates modification counter
│  ├─ Revert deep-copies data
│  └─ Revert does not modify original
│
├─ Save Operations (15+ tests)
│  ├─ Save writes changes to DuckDB
│  ├─ Save updates modification counter
│  ├─ Save makes saved_never true
│  ├─ Cannot save with invalid data
│  ├─ Save preserves types on DB
│  └─ Multiple saves cumulative
│
├─ Reactive Integration (5 tests)
│  ├─ Modification counter increments on edit
│  ├─ Modification counter resets on revert
│  ├─ Store trigger broadcasts changes
│  └─ Summary caching invalidates on save
│
└─ Error Conditions (12+ tests)
   ├─ Row out of bounds
   ├─ Column out of bounds
   ├─ Invalid type coercion
   └─ Database connection failure
```

#### Test Pattern

```r
test_that("update_cell validates row bounds", {
  # Arrange
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  
  # Act & Assert
  expect_error({
    store$update_cell(nrow(store$data) + 1, 1, "invalid")
  }, "Row index out of bounds")
  
  # Cleanup
  rm(store, con); gc()
})

test_that("save writes to DuckDB and updates baseline", {
  # Arrange
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  original_value <- store$data[1, 2]
  
  # Act
  store$update_cell(1, 2, "new_value")
  store$save()
  
  # Assert
  expect_equal(store$original[1, 2], "new_value")
  expect_equal(store$data[1, 2], "new_value")
  
  # Verify DB was written
  result <- DBI::dbReadTable(con, "mtcars")
  expect_equal(result[1, 2], "new_value")
  
  # Cleanup
  rm(store, con); gc()
})
```

**Key Pattern:** Each test owns database connection, cleans up with `rm() + gc()`

### 7. Error Handling (cli Package)

**Responsibility:** Rich, contextual error messages for debugging and user feedback  
**Location:** Used throughout (DataStore, utils, modules)  
**Pattern:** cli::cli_abort with multi-line context

#### Error Message Pattern

```r
tryCatch({
  # Operation
  coerce_value(value, col, data)
}, error = function(e) {
  cli::cli_abort(c(
    "Type coercion failed",           # Main message
    "i" = "Column: {col}",           # Context bullets
    "i" = "Value: {value}",
    "i" = "Expected type: {class}",
    "x" = "{conditionMessage(e)}"    # Original error
  ))
})
```

**Rendered as:**
```
Error in ...
Type coercion failed
ℹ Column: mpg
ℹ Value: abc
ℹ Expected type: numeric
✖ Error message
```

---

## File Category Reference

### Category 1: R6 Classes (`R/DataStore.R`)

**Purpose:** Single source of truth for application state  
**Export:** exported via run_app (indirectly), not directly exposed  
**Pattern:** R6 class with public/private methods, I/O in methods

```r
# Exported functions that use R6 internally
run_app()           # Creates DataStore internally
mod_table_server()  # Receives con, creates DataStore

# Write style guidelines
├─ Field naming: snake_case for private, UPPER_CASE for constants
├─ Method signatures: verb_noun(required, optional = default)
├─ Error handling: tryCatch with cli::cli_abort
├─ Documentation: roxygen with @export, @keywords internal, @details
└─ Cleanup: finalize() for connection close (if needed)
```

### Category 2: Shiny Modules (`R/mod_table.R`)

**Purpose:** Namespace-isolated UI + reactive logic  
**Exports:** `mod_table_ui`, `mod_table_server`  
**Pattern:** Pair of functions (UI + server) with consistent naming

```r
mod_table_ui <- function(id) {
  # Returns HTML/tags structure
}

mod_table_server <- function(id, con) {
  # Returns reactive store (optional)
}

# Write style guidelines
├─ Naming: mod_{feature}_{type} (e.g., mod_table_ui, mod_auth_server)
├─ Namespace: ns <- shiny::NS(id), use ns("input_name")
├─ Reactivity: explicit triggers (store_trigger), not implicit deps
├─ Events: observeEvent for all side effects
└─ Error handling: tryCatch + awn notifications
```

### Category 3: Utility Functions (`R/utils.R`)

**Purpose:** Validation, type coercion, data operations  
**Exports:** None (all @keywords internal, used by R6/modules)  
**Pattern:** Pure functions, composed in validation chains

```r
# Validation functions
validate_row(row, data)
validate_column(col, data)
coerce_value(value, col, data)
validate_no_na_loss(coerced, original, col)

# Data functions
load_mtcars_data(con)
write_mtcars_to_db(con, data)
set_mtcars_column_type(data)
calculate_column_means(data, numeric_cols)

# Write style guidelines
├─ Naming: function_verb_noun (validate_row, coerce_value, load_mtcars_data)
├─ Validation: checkmate assertions, then business logic
├─ Error messages: cli::cli_abort with context
├─ Return: Value on success, abort on error (no NULL returns for errors)
└─ Deterministic-first: Fast checks before slow operations
```

### Category 4: Custom HTMLWidgets (`R/hotwidget.R`, `inst/htmlwidgets/hotwidget.js`)

**Purpose:** Table editing with Handsontable, R↔JS communication  
**Exports:** `hotwidget`, `hotwidget_output`, `render_hotwidget`  
**Pattern:** R wrapper + JS factory, Shiny input binding

```r
# R wrapper
hotwidget(data, colTypes, rowHeaders, colHeaders)
hotwidget_output(outputId, width, height)
render_hotwidget(expr, env, quoted)

# JavaScript factory
HTMLWidgets.widget({ name: "hotwidget", factory: ... })

# Write style guidelines
├─ R: Input validation, parameter collection, createWidget
├─ JS: renderValue + resize methods, event batching with RAF
├─ Types: Column type → Handsontable type mapping
├─ Events: afterChange hook, Shiny.setInputValue for communication
└─ Performance: RAF debouncing for edit batching
```

### Category 5: Stylesheets (`inst/app/www/custom.css`)

**Purpose:** Enterprise design, responsive layout  
**Pattern:** Bootstrap 5 + custom overrides

```css
/* Structure */
.card-panel { /* Data containers */ }
.summary-metric { /* Summary boxes */ }
.action-buttons { /* Button groups */ }

/* Theme */
:root {
  --primary: #0066cc;
  --secondary: #e8f0f6;
  --danger: #dc3545;
}

/* Write style guidelines
├─ Bootstrap first (don't duplicate Bootstrap classes)
├─ BEM naming (.component__element--modifier)
├─ Mobile-first media queries
├─ CSS variables for theme (primary, secondary, danger)
└─ Handsontable overrides (.ht-table, .ht-cell, etc.)
```

### Category 6: Data Files (`inst/extdata/mtcars.duckdb`)

**Purpose:** Embedded database for demo/testing  
**Pattern:** DuckDB file, pre-populated with mtcars data

```r
# Write style guidelines
├─ Generate via: DBI::dbWriteTable(con, "mtcars", mtcars)
├─ Location: inst/extdata/{dataset}.duckdb (not gitignored)
├─ Size: Keep <5MB for package distribution
├─ Initialization: load_mtcars_data() reads at startup
└─ Updates: User saves overwrite file (transaction semantics)
```

### Category 7: Unit Tests (`tests/testthat/test-DataStore.R`, etc.)

**Purpose:** Fast feedback on correctness  
**Pattern:** testthat with Arrange-Act-Assert

```r
# Write style guidelines
├─ File naming: test-{module_name}.R
├─ Test naming: test_that("specific behavior", { })
├─ Setup: Create fresh resources per test (con, store, etc.)
├─ Teardown: rm(store, con); gc()
├─ Assertions: expect_equal, expect_error, expect_silent
├─ Database: Use real DuckDB (not mocked)
└─ Coverage: ~80% (critical paths, error conditions)
```

### Category 8: Test Configuration (`tests/testthat.R`, `tests/testthat/helpers.R`)

**Purpose:** Test framework setup, shared utilities  
**Pattern:** testthat initialization

```r
# testthat.R: Entry point
library(testthat)
library(editable)
test_check("editable")

# helpers.R: Shared utilities
establish_test_db <- function() {
  tempfile(fileext = ".duckdb")
}

# Write style guidelines
├─ testthat.R: Minimal, just test_check()
├─ helpers.R: Fixtures, factory functions
└─ DBI cleanup: Proper connection close in each test
```

### Category 9: Test Data (`tests/testthat/fixtures/`)

**Purpose:** Consistent data for tests  
**Pattern:** R files defining fixtures

```r
# fixtures/mtcars.R
mtcars_sample <- structure(
  list(mpg = c(21.0, 21.0), cyl = c(6, 6)),
  class = "data.frame"
)

# Write style guidelines
├─ File naming: {dataset}.R
├─ Small samples (rows < 20 for speed)
└─ Used via source() in test files
```

### Category 10: Test Snapshots (`tests/testthat/_snaps/`)

**Purpose:** Regression testing for rendered HTML, UI structures  
**Pattern:** Snapshot storage (auto-generated)

```r
# Auto-generated by shinytest2::expect_snapshot_value()
# Manual review required on first generation
# Update with shinytest2::snapshot_accept()
```

### Category 11: Development Documentation (root README.md, doc/)

**Purpose:** Installation, usage, contributing guide  
**Pattern:** Markdown files in root/doc

```md
# README.md
- What is this project?
- Quick start (install, run)
- Features overview
- Architecture overview
- Contributing guide
- License

# doc/DEVELOPMENT.md
- Dev environment setup
- Running tests
- Building package
- Deployment

# .github/CONTRIBUTING.md (Git-specific)
- Issue templates
- PR templates
- Code review guidelines
```

### Category 12: Dependency Management (`DESCRIPTION`, `renv/`)

**Purpose:** Package dependencies with reproducibility  
**Pattern:** DESCRIPTION imports + optional renv.lock

```r
# DESCRIPTION
Imports:
    shiny (>= 1.8.0),
    R6 (>= 2.5.1),
    DBI (>= 1.1.3),
    duckdb (>= 0.8.0),
    
# renv.lock (generated, committed to git)
{
  "R": { "Version": "4.3.2" },
  "Packages": { ... lockfile entries ... }
}

# Write style guidelines
├─ DESCRIPTION: Minimal versions (>= semantic)
├─ renv: Use for CI/production consistency
├─ Updates: Edit DESCRIPTION, then renv::snapshot()
└─ Restores: renv::restore() on new environment
```

### Category 13: Project Configuration (`editable.Rproj`, `.Rprofile`)

**Purpose:** RStudio + development settings  
**Pattern:** Project-level config files

```ini
# editable.Rproj
[RStudio config]
RestoreWorkspace: No
SaveWorkspace: No
EncodingType: UTF-8
PackageRoxygenize: rd,collate,namespace
```

### Category 14: Golem Configuration (`inst/golem-config.yml`)

**Purpose:** Feature flags, environment-specific settings  
**Pattern:** YAML with environment sections

```yaml
default:
  golem_name: editable
  app_prod: no
  
production:
  app_prod: yes
```

### Category 15: CI/CD Configuration (`.github/workflows/)

**Purpose:** Automated testing, deployment  
**Pattern:** GitHub Actions workflows (future)

```yaml
name: R-CMD-check
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: r-lib/actions/setup-r@v2
      - run: R CMD check .
```

---

## Feature Scaffold Guide

### How to Add a New Feature

**Example: Add Row Deletion**

#### 1. Requirement

Users should be able to delete rows from the table (with confirmation modal).

#### 2. R6 Method (DataStore)

```r
#' Delete row from dataset
#' @param row Integer. Row index (1-based).
delete_row <- function(row) {
  tryCatch({
    # Validate
    checkmate::assert_integerish(row, len = 1, lower = 1, upper = nrow(self$data))
    
    # Delete
    self$data <- self$data[-row, , drop = FALSE]
    self$modification_counter <- self$modification_counter + 1
    
    invisible(self)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to delete row",
      "i" = "Row index: {row}",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
```

#### 3. UI Component (R/mod_table.R)

```r
# Add to mod_table_ui
actionButton(
  ns("delete_row_btn"),
  "Delete Row",
  class = "btn btn-danger btn-sm",
  icon = icon("trash")
)
```

#### 4. Event Handler (R/mod_table.R)

```r
# Add to mod_table_server
observeEvent(input$delete_row_btn, {
  # Get selected row from Handsontable (requires JS integration)
  selected_row <- input$table_selected_row
  
  if (is.null(selected_row) || length(selected_row) == 0) {
    awn::awn("warning", "Please select a row to delete")
    return()
  }
  
  # Show confirmation modal
  showModal(modalDialog(
    title = "Delete Row",
    sprintf("Delete row %d? This cannot be undone.", selected_row),
    footer = tagList(
      actionButton(ns("delete_confirm"), "Yes, delete", class = "btn-danger"),
      modalButton("Cancel")
    )
  ))
})

observeEvent(input$delete_confirm, {
  tryCatch({
    selected_row <- input$table_selected_row
    store$delete_row(selected_row)
    store_trigger$increment()
    removeModal()
    awn::awn("success", sprintf("Row %d deleted", selected_row))
  }, error = function(e) {
    awn::awn("error", clean_error_message(conditionMessage(e)))
  })
})
```

#### 5. JavaScript Integration (inst/htmlwidgets/hotwidget.js)

```javascript
// Add to Handsontable config
afterSelectionEnd: function(r, c, r2, c2) {
  // Store selected row
  Shiny.setInputValue("table_selected_row", r + 1);  // 0→1 based
}
```

#### 6. Unit Tests (tests/testthat/test-DataStore.R)

```r
test_that("delete_row removes row from data", {
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  original_nrow <- nrow(store$data)
  
  store$delete_row(1)
  
  expect_equal(nrow(store$data), original_nrow - 1)
  expect_equal(store$modification_counter, 1)
  
  rm(store, con); gc()
})

test_that("delete_row validates row bounds", {
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  
  expect_error(
    store$delete_row(nrow(store$data) + 1),
    "out of bounds"
  )
  
  rm(store, con); gc()
})
```

#### 7. Integration Test (tests/testthat/test-shinytest2.R)

```r
test_that("Delete row workflow executes", {
  # app <- ShinyDriver$new(...)
  # app$click("delete_row_btn")
  # app$click("delete_confirm")
  # app$assert_silent()
})
```

**Checklist:**
- ✅ R6 method added with validation
- ✅ UI element added to module
- ✅ Event handler with modal confirmation
- ✅ JavaScript selected row tracking
- ✅ Unit tests for R6 method
- ✅ Integration test for Shiny flow
- ✅ Error handling at each layer
- ✅ Notifications to user

---

## Integration Rules

### Cross-Cutting Concerns

#### 1. Error Handling (Universal Rule)

**Rule:** All error paths use `cli::cli_abort` with context

```r
# ❌ Bad
stop("Invalid row")

# ✅ Good
cli::cli_abort(c(
  "Row update failed",
  "i" = "Row: {row}",
  "i" = "Valid bounds: [1, {nrow(data)}]",
  "x" = "{conditionMessage(e)}"
))
```

**Where:** DataStore methods, utils.R functions, observeEvent handlers

**Recipient:** User sees notification via awn::awn() in Shiny

#### 2. Validation (Multi-Phase Rule)

**Rule:** Deterministic checks before risky operations

```r
# Phase 1: Deterministic (fast)
validate_row(row, data)
validate_column(col, data)

# Phase 2: Risky (may fail)
tryCatch({
  coerce_value(value, col, data)
  validate_no_na_loss(coerced, value, col)
}, error = function(e) { ... })
```

**Where:** DataStore$update_cell, utils.R validation chain

**Benefit:** Fast feedback on obvious errors, rich context on surprises

#### 3. Reactivity (Explicit Trigger Rule)

**Rule:** No implicit reactive dependencies; use explicit `store_trigger`

```r
# ❌ Bad (implicit dependency on store$data)
# output$summary <- renderText({
#   store$data  # Implicit invalidation
# })

# ✅ Good (explicit trigger)
output$summary <- renderText({
  store_trigger()  # Explicit invalidation
  store$data
})
```

**Where:** mod_table_server renderText, renderUI, etc.

**Benefit:** Predictable invalidation, no surprising re-renders

#### 4. Type Safety (Immutability Rule)

**Rule:** Types preserved throughout; no silent type changes

```r
# DataStore initialization
self$original ← read_only snapshot (make deep copy)
self$data ← mutable working copy

# On load: apply set_mtcars_column_type
# On coerce: validate no NA loss
# On save: write back with types preserved
```

**Where:** DataStore initialization, coerce_value, save

**Benefit:** Pharma compliance; no data type surprises

#### 5. Session Lifecycle (Connection Rule)

**Rule:** Database connection stays open for session lifetime

```r
run_app <- function() {
  con <- establish_duckdb_connection(app_config$db_path)
  # Connection passed to app_server, used throughout
  # Auto-closes when con goes out of scope (garbage collection)
}
```

**Where:** run_app creates con, app_server receives, mod_table_server uses

**Benefit:** Connection pooling, consistent state

#### 6. Testing (Real Resources Rule)

**Rule:** Tests use real DuckDB, not mocks

```r
test_that("...", {
  # Setup: Real database
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  
  # Act & Assert
  store$update_cell(...)
  expect_equal(...)
  
  # Cleanup
  rm(store, con); gc()
})
```

**Where:** tests/testthat/test-*

**Benefit:** Catches integration issues, confidence in production

#### 7. Documentation (Roxygen Rule)

**Rule:** All exported functions must have @export, @description, @details

```r
#' Function Title (verb + noun)
#'
#' @description One sentence what does it do.
#'
#' @details
#' Extended explanation. Behavior notes.
#'
#' @param x Type. What is it.
#' @return Type. What is returned. NULL on error? Invisible?
#'
#' @examples
#' \dontrun{ }
#'
#' @export
my_function <- function(x) { }
```

**Where:** All functions in R/

**Benefit:** Auto-generated man pages, IDE autocomplete

---

## Code Patterns Reference

### Pattern 1: R6 Data Mutation

```r
#' Update Single Cell
update_cell <- function(row, col, value) {
  # Phase 1: Validate bounds
  validate_row(row, self$data)
  validate_column(col, self$data)
  
  # Phase 2: Coerce type
  coerced <- coerce_value(value, col, self$original)
  
  # Phase 3: Detect data loss
  validate_no_na_loss(coerced, value, col)
  
  # Phase 4: Update state
  self$data[row, col] <<- coerced
  self$modification_counter <<- self$modification_counter + 1
  
  invisible(self)
}
```

### Pattern 2: Validation Chain

```r
# Call sequence: update_cell → validate_row → validate_column → coerce_value → validate_no_na_loss

# Each function:
# - Takes specific domain (row index, col name, value)
# - Validates in isolation
# - Returns transformed value or throws
# - Error includes context

validate_row <- function(row, data) {
  if (row < 1 || row > nrow(data)) {
    cli::cli_abort("Row {row} out of bounds [1, {nrow(data)}]")
  }
}
```

### Pattern 3: Modal Confirmation

```r
# Button click → showModal
observeEvent(input$save_btn, {
  showModal(modalDialog(
    title = "Confirm",
    "Are you sure?",
    footer = tagList(
      actionButton(..., "Yes", class = "btn-danger"),
      modalButton("Cancel")
    )
  ))
})

# Modal confirmation → action
observeEvent(input$confirm, {
  tryCatch({
    store$save()
    removeModal()
    notification(...)
  }, error = function(e) {
    notification_error(...)
  })
})
```

### Pattern 4: Event Batching with RAF

```javascript
// JavaScript: Collect edits, schedule RAF
var edits = {};
var scheduled = false;

function onEdit(changes) {
  changes.forEach(c => {
    edits[c[0] + '_' + c[1]] = {row: c[0]+1, col: c[1]+1, val: c[3]};
  });
  
  if (!scheduled) {
    scheduled = true;
    requestAnimationFrame(() => {
      Shiny.setInputValue("edits", Object.values(edits));
      edits = {};
      scheduled = false;
    });
  }
}
```

### Pattern 5: Shiny Module Naming

```r
# UI function
mod_feature_ui <- function(id) {
  ns <- NS(id)
  # Return tagList()
}

# Server function
mod_feature_server <- function(id, parent_data) {
  moduleServer(id, function(input, output, session) {
    # React to parent_data
    # Create outputs
    # Return reactive() if parent needs data
  })
}

# Called as
mod_feature_ui("feature_1")
mod_feature_server("feature_1", reactive_parent_data)
```

### Pattern 6: Error Message Formatting

```r
# Use cli::cli_abort with bullet points
cli::cli_abort(c(
  " main_message",           # No bullet
  "i" = "info_bullet: {var}",
  "x" = "error_bullet: detail",
  "*" = "warning_bullet"
))

# Output to user via awn notification
awn::awn("error", clean_error_message(conditionMessage(e)))
```

### Pattern 7: Reactive Summary Stats

```r
# Create cached summary
self$summary_cache <- list(
  nrow = nrow(self$data),
  ncol = ncol(self$data),
  types = sapply(self$data, class),
  modified = self$modification_counter
)

# Return on demand
summary <- function() {
  list(
    rows = nrow(self$data),
    columns = ncol(self$data),
    column_types = sapply(self$data, class),
    modified_count = self$modification_counter
  )
}

# Use in Shiny output
output$summary <- renderText({
  store_trigger()  # Explicit invalidation
  s <- store$summary()
  sprintf("Rows: %d | Modified: %d cells", s$rows, s$modified_count)
})
```

---

## Example Prompt Usage

### Scenario 1: Adding a New Validation Rule

**User Prompt to Copilot:**
```
I need to add validation for date columns. 
The user should be able to enter dates like "2024-01-31" 
in ISO format and the system should reject invalid dates. 
Can you draft the validation function?
```

**Copilot Uses This Guide To:**
1. Look up "Validation Pattern" → Multi-phase approach (deterministic first)
2. Look up "Utility Functions" → Function should go in R/utils.R
3. Look up "Error Handling" → Use cli::cli_abort with context
4. Check "Type Coercion Pattern" → Reference how coerce_value works
5. Implement:

```r
#' Validate Date Format
#' @keywords internal
validate_date_format <- function(value, col_name) {
  tryCatch({
    if (is.na(value)) return(invisible(TRUE))
    
    # Deterministic check
    if (!is.character(value)) {
      stop("Date must be character")
    }
    
    # Pattern check
    if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", value)) {
      stop("Invalid format, must be YYYY-MM-DD")
    }
    
    # Try parse
    parsed <- as.Date(value)
    if (is.na(parsed)) {
      stop("Invalid date value")
    }
    
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Date validation failed",
      "i" = "Column: {col_name}",
      "i" = "Value: {value}",
      "i" = "Expected format: YYYY-MM-DD",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
```

### Scenario 2: Adding a Modal Feature

**User Prompt to Copilot:**
```
Add an "Export Data" button that shows a modal 
letting users choose between CSV and Excel formats, 
then exports the data to their computer.
```

**Copilot Uses This Guide To:**
1. Look up "Shiny Modules" → Add button + modal in mod_table_ui
2. Look up "Event Handler Pattern" → Use observeEvent + showModal
3. Look up "File Download" → Use downloadButton (if Shiny supports)
4. Look up "Error Handling" → Wrap export in tryCatch + awn notification
5. Implement:

```r
# In mod_table_ui
downloadButton(ns("export_data"), "Export Data", class = "btn-primary")

# In mod_table_server
observeEvent(input$export_data, {
  showModal(modalDialog(
    title = "Export Data",
    selectInput(ns("format_choice"), 
      "Choose format:", 
      c("CSV" = "csv", "Excel" = "xlsx")
    ),
    footer = tagList(
      actionButton(ns("export_confirm"), "Export", class = "btn-primary"),
      modalButton("Cancel")
    )
  ))
})

observeEvent(input$export_confirm, {
  tryCatch({
    format <- input$format_choice
    data <- store$data
    
    # Export logic...
    
    removeModal()
    awn::awn("success", "Data exported")
  }, error = function(e) {
    awn::awn("error", clean_error_message(conditionMessage(e)))
  })
})
```

### Scenario 3: Debugging State Issue

**User Prompt to Copilot:**
```
The modification counter isn't resetting after revert. 
I see DataStore$modification_counter  is being incremented 
but the UI isn't reflecting the change. 
What's the issue?
```

**Copilot Uses This Guide To:**
1. Look up "State Management" → Understand modification_counter lifecycle
2. Look up "Reactivity (Explicit Trigger Rule)" → Must call store_trigger$increment()
3. Check if observeEvent calls store_trigger after revert
4. Identify: Likely missing `store_trigger$increment()` in revert handler
5. Debug fix:

```r
# Old (buggy)
observeEvent(input$revert_btn, {
  store$revert()  # This increments modification_counter in R6
  # But doesn't invalidate Shiny reactives!
})

# Fixed
observeEvent(input$revert_btn, {
  store$revert()
  store_trigger$increment()  # Explicitly invalidate
  awn::awn("success", "Reverted")
})
```

### Scenario 4: Writing Tests

**User Prompt to Copilot:**
```
I added a new method DataStore$export_to_csv(). 
Can you write unit tests for it?
```

**Copilot Uses This Guide To:**
1. Look up "Testing" → Location: tests/testthat/test-DataStore.R
2. Look up "Test Pattern" → Arrange-Act-Assert, own connection per test
3. Look up "Real Resources Rule" → Don't mock DuckDB
4. Implement tests:

```r
test_that("export_to_csv writes valid CSV", {
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  
  csv_file <- tempfile(fileext = ".csv")
  store$export_to_csv(csv_file)
  
  expect_true(file.exists(csv_file))
  
  result <- read.csv(csv_file)
  expect_equal(nrow(result), nrow(store$data))
  expect_equal(ncol(result), ncol(store$data))
  
  rm(store, con); gc()
})

test_that("export_to_csv validates file path", {
  con <- establish_duckdb_connection(temp_db)
  store <- DataStore$new(con)
  
  expect_error({
    store$export_to_csv("/invalid/path/file.csv")
  }, "Cannot write to path")
  
  rm(store, con); gc()
})
```

---

## FAQ for Copilot Usage

**Q: Which file should I edit?**
A: Follow the File Category Reference. Validation → R/utils.R. UI logic → R/mod_table.R. Data → R/DataStore.R.

**Q: How do I know if something is exported?**
A: Look for @export tag in roxygen documentation. If it has @export, it's in the public API.

**Q: Where do I add error handling?**
A: Always wrap risky operations (database, type coercion, UI actions) in tryCatch, use cli::cli_abort on failure.

**Q: How do I test my changes?**
A: Add test to tests/testthat/test-{module}.R following Arrange-Act-Assert pattern. Use real DuckDB connection.

**Q: Why doesn't my reactive invalidate?**
A: Check if your output function calls store_trigger() explicitly. Implicit dependencies don't work per design.

**Q: How do I pass data between modules?**
A: Modules return reactives. Parent calls mod_server <- mod_table_server("id", parent_data). Parent can observe(mod_server()).

**Q: What's the pattern for user confirmation?**
A: Button → showModal → modalDialog with actionButton + modalButton → observeEvent on actionButton → tryCatch action → removeModal, notification.

---

## Summary

This document provides definitive guidance for AI assistants on developing features in **editable**. It combines:

1. **Architecture overview** (7 domains with constraints)
2. **File taxonomy** (15 categories with patterns)
3. **Code patterns** (validation chains, R6 mutation, modals, RAF debouncing)
4. **Integration rules** (error handling, type safety, explicit reactivity)
5. **Test patterns** (real resources, Arrange-Act-Assert)
6. **Example scenarios** (adding validation, modals, exports, debugging)

**For best results:**
- Always start with the Architecture section to understand domain
- Consult File CategoryReference for where to place code
- Follow Code Patterns for implementation
- Check Integration Rules for cross-cutting concerns
- Use Example Prompt Usage as a starting point for your specific task

---

**End of Copilot Instructions**

---

## Appendix: Referenced Documentation Files

The following files were generated as part of the instruction-generation process and provide additional context:

- `.project_doc/1-determine-techstack.md` — Technology stack analysis by domain
- `.project_doc/2-file-categorization.json` — All 15 file categories mapped
- `.project_doc/3-architectural-domains.json` — 7 domains with constraints
- `.project_doc/4-domains/*.md` — Deep dives on state management, validation, persistence, UI, widgets, testing
- `.project_doc/5-style-guides/*.md` — Style guides for R6 classes, Shiny modules, utilities, widgets, entry points, package config

All files referenced in this document (NAMESPACE, DESCRIPTION, test files) follow the patterns defined in their respective style guides.
