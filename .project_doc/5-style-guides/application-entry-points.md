# Application Entry Points Style Guide

## Overview

Application entry points define how the Shiny application starts, loads configuration, and initializes dependencies. In editable, entry points include:
- `app.R` — Local development launcher
- `R/run_app.R` — Public API for running app
- `R/app_config.R` — Configuration management
- `R/app_ui.R` — Main UI definition
- `R/app_server.R` — Main server initialization

## File Convention

**Development Entry Point**: `app.R`
**Package Entry Point**: `R/run_app.R` (exported function)
**Configuration**: `R/app_config.R` (internal utilities)
**UI Definition**: `R/app_ui.R` (internal, called by run_app)
**Server Definition**: `R/app_server.R` (internal, called by run_app)

## Local Development Entry Point

### app.R Pattern

```r
# app.R - Development launcher for working locally

# Performance profiling setup (optional, development only)
if (interactive()) {
  # Preload package without full R CMD check
  pkgload::load_all()
  
  # Optional: Attach development helpers
  library(shiny)
  library(dplyr)
}

# Run application
editable::run_app()
```

**Rules:**
- Minimal code, just load package and call run_app()
- Use `pkgload::load_all()` for interactive development
- Do NOT put business logic here
- Do NOT define UI, server, or reactive code
- Use `editable::` prefix (explicit namespace)

### Why Separate from run_app.R?

- `app.R` is NOT packaged (git-ignored in some workflows)
- `app.R` may vary per developer (local configuration)
- `run_app.R` is the stable, exported API

## Public API Entry Point

### run_app.R Pattern

```r
#' Run editable Shiny Application
#'
#' @description
#' Main entry point for application execution.
#' Initializes all configuration, loads data, starts Shiny app.
#'
#' @details
#' ## Initialization Sequence
#'
#' 1. Load configuration (app_config.R)
#' 2. Establish database connection
#' 3. Create UI (app_ui.R)
#' 4. Create server (app_server.R)
#' 5. Start Shiny app
#'
#' ## Performance Optimization
#'
#' - Package preloading (via pkgload in development)
#' - Database connection pooling (DuckDB via con object)
#' - Reactive architecture (explicit invalidation)
#'
#' @param options List. Shiny app options (port, host, browser, etc.).
#'   Override defaults with `shinyApp(..., options = list(port = 3000))`.
#'
#' @return Invisible NULL. Starts interactive Shiny session.
#'
#' @examples
#' \dontrun{
#'   # Run with defaults
#'   run_app()
#'
#'   # Run on specific port
#'   run_app(options = list(port = 3000))
#' }
#'
#' @export
run_app <- function(options = list()) {
  # 1. Configuration phase
  app_config <- get_app_config()
  
  # 2. Data & connection phase
  # Initialize database connection
  con <- establish_duckdb_connection(
    app_config$db_path,
    read_only = FALSE
  )
  
  # Preload data to test connection
  tryCatch({
    initial_data <- load_mtcars_data(con, table = "mtcars")
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to load initial data",
      "x" = "{conditionMessage(e)}"
    ))
  })
  
  # 3. UI definition phase
  app_ui <- app_ui(id = "app")
  
  # 4. Server initialization phase
  app_server_func <- function(input, output, session) {
    app_server(input, output, session, con)
  }
  
  # 5. Shiny app startup
  shiny::shinyApp(
    ui = app_ui,
    server = app_server_func,
    options = options
  )
}
```

**Rules:**
- Exported with @export
- One clear responsibility: orchestrate initialization
- Delegate to app_ui.R and app_server.R
- Error handling at initialization stage
- Documentation describes initialization sequence
- Options parameter for customization

## Configuration Management

### app_config.R Pattern

```r
#' Get Application Configuration
#'
#' @description
#' Centralizes configuration: paths, feature flags, defaults.
#' Separates configuration from code.
#'
#' @return List with named elements:
#'   - `db_path`: Character. Path to DuckDB database file.
#'   - `db_table`: Character. Primary table name ("mtcars").
#'   - `enable_export`: Logical. Allow data export? Default: TRUE.
#'   - `max_rows_display`: Integer. Pagination row limit.
#'
#' @keywords internal
get_app_config <- function() {
  list(
    # Database paths
    db_path = system.file(
      "extdata", "mtcars.duckdb",
      package = "editable"
    ),
    db_table = "mtcars",
    
    # Feature flags
    enable_export = TRUE,
    enable_import = FALSE,  # Future: multi-dataset support
    enable_audit_log = FALSE,  # Future: compliance features
    
    # UI configuration
    max_rows_display = 50,
    theme_primary = "#0066cc",
    theme_secondary = "#e8f0f6",
    
    # Performance
    debounce_edit_ms = 300,  # RAF debouncing window
    cache_summary_stats = TRUE,
    summary_cache_ttl_sec = 60,
    
    # Development
    debug_mode = FALSE,
    log_sql_queries = FALSE
  )
}

#' Validate and Get Configuration
#'
#' @description
#' Validates configuration values are reasonable.
#' Used at startup to catch misconfiguration.
#'
#' @param config List from get_app_config().
#'
#' @return Invisible list. Throws cli_abort if invalid.
#'
#' @keywords internal
validate_app_config <- function(config) {
  tryCatch({
    # Path validation
    checkmate::assert_file_exists(config$db_path, access = "r")
    
    # Table name validation
    checkmate::assert_character(config$db_table, len = 1, pattern = "^[a-zA-Z_][a-zA-Z0-9_]*$")
    
    # Numeric bounds
    checkmate::assert_integer(config$max_rows_display, lower = 1, upper = 1000)
    checkmate::assert_integer(config$debounce_edit_ms, lower = 50, upper = 2000)
    
    # Feature flags (logical)
    checkmate::assert_logical(config$enable_export, len = 1, null.ok = FALSE)
    checkmate::assert_logical(config$debug_mode, len = 1, null.ok = FALSE)
    
    invisible(config)
  }, error = function(e) {
    cli::cli_abort(c(
      "Application configuration invalid",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
```

**Pattern:**
- Single source of truth for configuration
- List of named elements (not environment variables)
- Defaults appropriate for production
- Validation function for startup checks
- Features grouped by concern (database, ui, performance, development)

## UI Definition

### app_ui.R Pattern

```r
#' Create Application UI
#'
#' @description
#' Defines main UI layout and components.
#' Called once at app startup by run_app.
#'
#' @param id Character. Shiny module namespace ID (always "app" at top-level).
#'
#' @return Shiny UI object (tagList or page function result).
#'
#' @keywords internal
app_ui <- function(id) {
  ns <- shiny::NS(id)
  
  # Main layout
  shiny::fluidPage(
    # Configuration
    theme = bslib::bs_theme(
      version = 5,
      primary = "#0066cc",
      secondary = "#e8f0f6",
      font_scale = 1.0
    ),
    
    # Meta tags for browser
    tags$head(
      tags$meta(charset = "UTF-8"),
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
      tags$title("editable — Data Editor"),
      
      # Custom CSS
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css")
    ),
    
    # Header
    tags$header(
      tags$nav(class = "navbar navbar-dark bg-primary",
        tags$div(class = "container-fluid",
          tags$span(class = "navbar-brand", "editable"),
          tags$span(class = "navbar-text text-light", "Data Editor")
        )
      )
    ),
    
    # Main content
    tags$main(class = "container-fluid",
      tags$div(class = "row my-4",
        tags$div(class = "col-12",
          # Call mod_table UI module
          mod_table_ui(ns("table"))
        )
      )
    ),
    
    # Footer
    tags$footer(class = "mt-5 pt-3 border-top text-muted",
      tags$div(class = "container-fluid",
        "editable | Data Editing Application"
      )
    )
  )
}

#' Get Application Stylesheet Path
#'
#' @description
#' Returns path to custom CSS relative to www/ folder.
#'
#' @return Character. URL path for inclusion in UI.
#'
#' @keywords internal
get_app_stylesheet <- function() {
  system.file("app/www/custom.css", package = "editable")
}
```

**Rules:**
- Namespace ID always "app" at top level
- Define layout with standard Bootstrap 5 structure
- Load custom CSS from inst/app/www/
- Call module UI functions with namespaced IDs
- No reactive code (pure structure definition)
- No hardcoded strings (use configuration)

## Server Definition

### app_server.R Pattern

```r
#' Create Application Server
#'
#' @description
#' Initializes server-side logic and module instances.
#' Called once at startup by run_app with connection object.
#'
#' @param input Shiny input object.
#' @param output Shiny output object.
#' @param session Shiny session object.
#' @param con DBI connection object. Active DuckDB connection.
#'
#' @return Invisible NULL. Modifies input/output/session via side effects.
#'
#' @keywords internal
app_server <- function(input, output, session, con) {
  # 1. Create module instances (one per feature)
  mod_table_server(
    id = "table",
    con = con
  )
  
  # 2. Global observers (cross-module communication if needed)
  # Not common; prefer module-specific logic
  
  # 3. Session lifecycle
  shiny::onSessionEnded(function() {
    cli::cli_inform("Session ended")
    # Cleanup: connection closed automatically via on_exit in parent
  })
}
```

**Rules:**
- Receives pre-established database connection
- Delegates to module server functions
- Minimal global/cross-module logic
- Session cleanup (connections close on parent scope exit)

## Configuration Options

```r
# Example: Custom options for run_app()

# Run on port 8000, external accessible
run_app(options = list(
  port = 8000,
  host = "0.0.0.0",
  launch.browser = FALSE
))

# Run in background
shinyD <- run_app(options = list(
  launch.browser = FALSE
))

# Run with custom logger
run_app(options = list(
  shiny.trace = TRUE,  # Enable request tracing
  shiny.sanitize.errors = FALSE  # Show full errors (dev only)
))
```

## Initialization Order & Error Handling

```r
run_app <- function(options = list()) {
  tryCatch({
    # Phase 1: Config validation
    app_config <- get_app_config()
    validate_app_config(app_config)
    
    # Phase 2: Database connection
    cli::cli_inform("Establishing database connection...")
    con <- establish_duckdb_connection(app_config$db_path)
    
    # Phase 3: Test database access
    cli::cli_inform("Loading initial dataset...")
    test_data <- load_mtcars_data(con, table = app_config$db_table)
    cli::cli_inform("Loaded {nrow(test_data)} rows from {app_config$db_table}")
    
    # Phase 4: Create UI & Server
    ui <- app_ui(id = "app")
    server <- function(input, output, session) {
      app_server(input, output, session, con)
    }
    
    # Phase 5: Start Shiny app
    cli::cli_inform("Starting Shiny application...")
    shiny::shinyApp(ui = ui, server = server, options = options)
    
  }, error = function(e) {
    cli::cli_abort(c(
      "Application startup failed",
      "x" = "{conditionMessage(e)}",
      "i" = "Check database path and configuration"
    ))
  })
}
```

**Pattern:**
- Sequential phases with clear milestones
- User feedback at each phase (cli_inform)
- Early validation (phase 1)
- Test database before app starts
- Aggregate errors with context

## Documentation Standards

All entry point functions documented with:

1. **@description**: What this function does (`run_app()` starts the app)
2. **@details**: 
   - Initialization sequence (numbered list)
   - Performance optimizations
   - Relevant configuration
3. **@param**: Document all parameters
4. **@return**: What happens (invisible NULL for run_app, list for get_app_config)
5. **@examples**: How to call with custom options
6. **@keywords internal**: If not exported

## Summary

Application entry points follow a **layered initialization pattern**:

1. **Entry Points**:
   - `app.R`: Development launcher (minimal code)
   - `run_app.R`: Public API (exported)

2. **Initialization**:
   - Configuration validation
   - Resource allocation (database connection)
   - UI creation
   - Server setup

3. **Configuration**:
   - Single source of truth (get_app_config)
   - Validation (validate_app_config)
   - Feature flags and defaults

4. **UI/Server**:
   - Pure structure definition (app_ui.R)
   - Module coordination (app_server.R)
   - Session lifecycle management

Key principle: **Separate startup orchestration from UI/server logic.**
