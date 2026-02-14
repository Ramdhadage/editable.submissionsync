# Shiny Modules Style Guide

## Overview

Shiny modules in editable follow the **UI + Server pattern** with explicit namespace isolation and reactive dependency management. Modules encapsulate both interface and logic for specific features.

## Module Naming Convention

**Pattern**: `mod_{feature}_{type}.(R|js|css)`

Examples:
- `R/mod_table.R` - Table module (UI + Server)
- `inst/htmlwidgets/hotwidget.js` - Associated custom widget
- `inst/app/www/custom.css` - Associated styles

## File Structure

**File**: `R/mod_table.R`

```r
# ============================================================================
# MODULE: Table (Data Table Editing)
# ============================================================================
# Purpose: Displays editable data table with live summary
# Dependencies: hotwidget htmlwidget, DataStore R6 class
# ============================================================================

# UI FUNCTION ----------------------------------------------------------

#' Table Module UI
#'
#' @param id Character string. Module namespace ID
#'
#' @return tagList of UI components
#' @export
mod_table_ui <- function(id) {
  ns <- shiny::NS(id)
  
  shiny::tagList(
    # UI elements
  )
}

# SERVER FUNCTION -------------------------------------------------------

#' Table Module Server
#'
#' @param id Character string. Module namespace ID
#' @param store_reactive Reactive value containing DataStore R6 object
#' @param store_trigger Reactive value for triggering updates
#'
#' @return Module server function
#' @export
mod_table_server <- function(id, store_reactive, store_trigger) {
  shiny::moduleServer(id, function(input, output, session) {
    # Server logic
  })
}
```

## UI Function Structure

```r
mod_table_ui <- function(id) {
  # Create namespace function
  ns <- shiny::NS(id)
  
  # Return tagList of UI elements
  shiny::tagList(
    # ACTION BUTTONS SECTION
    div(
      class = "action-buttons",
      actionButton(ns("save"), "Save"),
      actionButton(ns("revert"), "Revert")
    ),
    
    # MAIN CONTENT SECTION
    bslib::layout_columns(
      col_widths = c(10, 2),
      
      bslib::card(
        class = "card-panel",
        bslib::card_header("Table"),
        bslib::card_body(
          hotwidgetOutput(ns("table"), height = "500px")
        )
      ),
      
      bslib::card(
        class = "summary-panel",
        bslib::card_header("Summary"),
        bslib::card_body(
          # Summary content
        )
      )
    )
  )
}
```

**Rules:**
- Start with: `ns <- shiny::NS(id)`
- Wrap ALL input/output IDs with `ns()`
- Organize UI into logical sections with comments
- Use bslib components (page_navbar, nav_panel, card, layout_columns)
- Use semantic HTML (strong, p, div with classes)
- End with: Return `shiny::tagList(...)`

## Namespace Convention

### The Critical Rule: Always Use `ns()`

```r
# WRONG (will cause ID conflicts)
actionButton("save", "Save")
textOutput("summary_rows")

# CORRECT (isolated to module namespace)
actionButton(ns("save"), "Save")
textOutput(ns("summary_rows"))
```

**Result:**
- `mod_table_ui("table")` generates:
  - Input ID: `table-save` (not `save`)
  - Output ID: `table-summary_rows`
  - Referenced in server as: `input$save`, `output$summary_rows`

## Server Function Structure

```r
mod_table_server <- function(id, store_reactive, store_trigger) {
  # moduleServer creates isolated namespace
  shiny::moduleServer(id, function(input, output, session) {
    
    # PHASE 1: LOCAL REACTIVES & STATE
    table_data <- shiny::reactive({
      store_trigger()
      store <- store_reactive()
      if (is.null(store$data)) data.frame() else store$data
    })
    
    edit_batch <- reactiveVal(NULL)
    edit_timer <- reactiveVal(NULL)
    
    # PHASE 2: INITIALIZE STATE
    shinyjs::disable("save")
    shinyjs::disable("revert")
    
    # PHASE 3: OUTPUT RENDERING
    output$table <- renderHotwidget({
      hotwidget(data = table_data())
    })
    
    output$summary_rows <- renderText({
      store_trigger()
      store <- store_reactive()
      as.character(store$summary()$rows)
    })
    
    # PHASE 4: REACTIVE OBSERVERS
    shiny::observeEvent(input$table_edit, {
      # Handle cell edit
    })
    
    shiny::observeEvent(input$save, {
      # Handle save action
    })
    
    shiny::observeEvent(input$revert, {
      # Handle revert action
    })
    
  })
}
```

**Organization:**
1. Local reactive values for module state
2. Initialize UI state (disable buttons, etc.)
3. Define output renderers
4. Define event observers
5. No direct DOM manipulation

## Reactive Data Pattern

### Dependent on External State

```r
# Reactively depend on store_trigger explicitly
table_data <- shiny::reactive({
  store_trigger()          # Force update when trigger changes
  store <- store_reactive()  # Read current store
  
  if (is.null(store$data)) {
    return(data.frame())
  }
  
  store$data
})

# Use the reactive in rendering
output$table <- renderHotwidget({
  data <- table_data()
  hotwidget(data = data)
})
```

**Rules:**
- Explicitly reference the reactive trigger as first line
- Read R6 object second
- Add guards for null/empty states
- Reactives are lazy (computed when accessed)

### Multiple Outputs with Same Dependency

```r
# All depend on store_trigger
output$summary_rows <- renderText({
  store_trigger()
  store <- store_reactive()
  as.character(store$summary()$rows)
})

output$summary_cols <- renderText({
  store_trigger()
  store <- store_reactive()
  as.character(store$summary()$cols)
})

output$summary_mpg <- renderText({
  store_trigger()
  store <- store_reactive()
  summary <- store$summary()
  if (!is.null(summary$numeric_means) && "mpg" %in% names(summary$numeric_means)) {
    sprintf("%.1f", summary$numeric_means["mpg"])
  } else {
    "N/A"
  }
})
```

**Rules:**
- Each output independently depends on store_trigger
- Prevents unnecessary parent updates
- Clear, explicit dependency declaration

## Event Handler Pattern

### Simple Action (Button Click)

```r
shiny::observeEvent(input$revert, {
  tryCatch({
    store_reactive()$revert()
    store_trigger(store_trigger() + 1)
    
    shinyjs::disable("save")
    shinyjs::disable("revert")
    
    awn::notify("Data reverted to original state", type = "success")
    
  }, error = function(e) {
    error_msg <- conditionMessage(e)
    clean_msg <- clean_error_message(error_msg)
    awn::notify(
      paste("Revert failed:", clean_msg),
      type = "error"
    )
  })
})
```

**Pattern:**
- Wrap in `tryCatch` for error handling
- Call R6 methods on store
- Increment `store_trigger()` to invalidate dependents
- Update UI state (disable/enable buttons)
- Show user feedback via notifications

### Complex Action (Modal + Confirmation)

```r
shiny::observeEvent(input$save, {
  modified_count <- store_reactive()$get_modified_count()
  
  shiny::showModal(
    shiny::modalDialog(
      title = "Confirm Save to Database",
      shiny::p("You are about to save your changes to the DuckDB database."),
      shiny::p(
        shiny::strong("Important:"),
        " Saved changes will become the new baseline and cannot be reverted."
      ),
      shiny::p(sprintf("Modified cells: %d", modified_count)),
      footer = shiny::tagList(
        shiny::modalButton("Cancel"),
        shiny::actionButton(
          session$ns("confirm_save"),
          "Save to DuckDB",
          class = "btn btn-primary"
        )
      ),
      easyClose = TRUE
    )
  )
})

shiny::observeEvent(input$confirm_save, {
  tryCatch({
    store_reactive()$save()
    store_trigger(store_trigger() + 1)
    shinyjs::disable("save")
    shinyjs::disable("revert")
    shiny::removeModal()
    
    awn::notify(
      "Changes saved to DuckDB successfully",
      type = "success"
    )
  }, error = function(e) {
    shiny::removeModal()
    awn::notify(
      paste("Save failed:", conditionMessage(e)),
      type = "alert"
    )
  })
})
```

**Pattern:**
- First observer shows modal/dialog
- Second observer handles confirmation
- Use `session$ns()` in nested input IDs
- `removeModal()` on completion
- Error handling wraps both observers

## Input Binding for Custom Widgets

```r
shiny::observeEvent(input$table_edit, {
  edit <- input$table_edit
  
  if (is.null(edit$row) || is.null(edit$col) || is.null(edit$value)) {
    warning("Invalid edit received from widget: missing fields")
    return()
  }
  
  # Queue the edit
  edit_batch(edit)
  
  # Schedule processing with RAF debouncing
  raf_code <- "
    (function() {
      var rafId = requestAnimationFrame(function() {
        Shiny.setInputValue('table-_raf_trigger', Math.random());
      });
      return rafId;
    })()
  "
  raf_id <- shinyjs::runjs(raf_code)
  edit_timer(raf_id)
})

shiny::observeEvent(input$`_raf_trigger`, {
  edit <- edit_batch()
  if (is.null(edit)) return()
  
  tryCatch({
    r_row <- edit$row + 1  # Convert 0-based to 1-based
    
    store_reactive()$update_cell(
      row = r_row,
      col = edit$col,
      value = edit$value
    )
    
    store_trigger(store_trigger() + 1)
    shinyjs::enable("save")
    shinyjs::enable("revert")
    
  }, error = function(e) {
    error_msg <- conditionMessage(e)
    clean_msg <- clean_error_message(error_msg)
    awn::notify(
      paste("Update failed:", clean_msg),
      type = "alert"
    )
    store_trigger(store_trigger() + 1)  # Redraw
  })
  
  edit_batch(NULL)
  edit_timer(NULL)
})
```

**Pattern:**
- First observer queues the edit from custom widget
- Second observer processes via RAF (debouncing)
- Convert indices if needed (JS 0-based → R 1-based)
- Error handling shows feedback and redraws UI

## Session Scoping

### Accessing Session Information

```r
mod_table_server <- function(id, store_reactive, store_trigger) {
  shiny::moduleServer(id, function(input, output, session) {
    
    # session$ns() for scoped IDs
    button_id <- session$ns("confirm_save")
    
    # session available for all Shiny functions
    shiny::removeModal()
    
    # Don't return anything from moduleServer
  })
}
```

**Rules:**
- `session` automatically passed to moduleServer
- Use `session$ns()` for scoped IDs in nested modals
- All Shiny functions available via session
- Don't return anything from moduleServer

## Documentation

```r
#' Table Module UI
#'
#' @description
#' Returns UI for interactive data table with live editing.
#' Includes table display and real-time summary statistics.
#'
#' @param id Character string. Module namespace ID (must match server).
#'
#' @return tagList of UI components
#'
#' @section UI Structure:
#' - Action buttons (Save, Revert)
#' - Main card with hotwidget table (10-column layout)
#' - Summary card with statistics (2-column layout)
#'
#' @examples
#' \dontrun{
#' mod_table_ui("table")
#' }
#'
#' @export
mod_table_ui <- function(id) { ... }

#' Table Module Server
#'
#' @description
#' Manages table data, editing, and database persistence.
#'
#' @param id Character string. Module namespace ID (must match UI).
#' @param store_reactive Reactive value containing DataStore R6 object.
#' @param store_trigger Reactive value used to force invalidation.
#'
#' @return Module server function (for testServer compatibility)
#'
#' @section Reactivity Pattern:
#' This module uses explicit invalidation via reactiveVal():
#' - Reading store_reactive() depends on it changing
#' - Writing store_reactive()$method() requires store_trigger() increment
#' - All dependents explicitly reference store_trigger()
#'
#' @sections Behavior:
#' - Starts with save/revert buttons disabled
#' - Enables buttons on first edit
#' - Disables buttons after save/revert
#' - All edits validated in R6 before display update
#'
#' @examples
#' \dontrun{
#' store <- DataStore$new()
#' store_reactive <- reactiveVal(store)
#' store_trigger <- reactiveVal(0)
#' mod_table_server("table", store_reactive, store_trigger)
#' }
#'
#' @export
mod_table_server <- function(id, store_reactive, store_trigger) { ... }
```

## Summary

Shiny modules in this project emphasize:
- **Isolation**: Namespace prevents ID conflicts
- **Clarity**: Explicit reactive dependencies
- **Responsibility Separation**: UI focuses on layout; server handles logic
- **Error Resilience**: All risky operations wrapped in tryCatch
- **User Feedback**: Clear notifications for success and failure

Key principle: **Modules are self-contained, reusable, and unaware of parent context.**
