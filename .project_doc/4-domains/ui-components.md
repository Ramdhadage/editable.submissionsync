# UI Components Domain

## Overview

The UI architecture follows **Shiny module pattern** with **Bootstrap 5 theming** via bslib. Key principles:
- All UI encapsulated in reusable modules
- Namespace isolation for DOM elements
- Reactive outputs tied explicitly to store state
- Component composition via bslib layout functions

## Main Application Structure

### App UI (app_ui.R)

```r
app_ui <- function(request) {
  tagList(
    golem_add_external_resources(),
    shinyjs::useShinyjs(),
    awn::useAwn(),
    
    bslib::page_navbar(
      title = "Data Explorer",
      id = "navbar",
      theme = bslib::bs_theme(version = 5),
      fillable = TRUE,
      
      bslib::nav_spacer(),
      
      bslib::nav_panel(
        title = "Home",
        value = "home",
        strong(h1("MTCars Dataset")),
        p("Interactive data table with real-time editing"),
        skeleton_replacement_script("table"),
        skeleton_content("table"),
        mod_table_ui("table")
      ),
      
      bslib::nav_panel(title = "Analytics", value = "analytics"),
      bslib::nav_panel(title = "Settings", value = "settings")
    )
  )
}
```

**Structure:**
- `page_navbar()`: Multi-page layout with tabbed navigation
- `nav_panel()`: Individual pages (Home, Analytics, Settings)
- `nav_spacer()`: Pushes subsequent nav items to the right
- Module inclusion: `mod_table_ui("table")`
- Loading skeleton: `skeleton_replacement_script()` and `skeleton_content()`

### Resource Management

```r
golem_add_external_resources <- function() {
  add_resource_path(
    "www",
    app_sys("app/www"),
  )
  
  tags$head(
    favicon(),
    bundle_resources(
      path = app_sys("app/www"),
      app_title = "Interactive Excel-Style Data Editor"
    )
  )
}
```

**Purpose:**
- Registers static assets (`/www`)
- Adds favicon
- Bundles Golem resources

## Table Module: UI

### Module UI Definition

```r
mod_table_ui <- function(id) {
  ns <- shiny::NS(id)
  
  shiny::tagList(
    # Action buttons
    div(
      class = "action-buttons mb-3 save-revert-buttons",
      actionButton(
        ns("save"),
        "Save Changes",
        class = "btn btn-outline-secondary"
      ),
      actionButton(
        ns("revert"),
        "Revert Changes",
        icon = icon("undo"),
        class = "btn btn-outline-danger"
      )
    ),
    
    # Main content: Table + Summary
    bslib::layout_columns(
      col_widths = c(10, 2),
      
      bslib::card(
        class = "card-panel",
        bslib::card_header("Data Table"),
        bslib::card_body(
          hotwidgetOutput(ns("table"), height = "500px")
        )
      ),
      
      bslib::card(
        class = "summary-panel",
        bslib::card_header("Summary"),
        bslib::card_body(
          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Records"),
            div(class = "summary-metric-value", textOutput(ns("summary_rows"), inline = TRUE))
          ),
          # ... more metrics ...
        )
      )
    )
  )
}
```

**Key Features:**
- `ns <- shiny::NS(id)`: Namespace function for DOM isolation
- All input/output IDs wrapped with `ns()`: `ns("save")` → `table-save`
- Layout via `bslib::layout_columns(col_widths = c(10, 2))`
- Cards via `bslib::card()` with headers and bodies

### Namespace Convention

Namespace ensures no DOM ID conflicts:
- UI calls: `mod_table_ui("table")`
- Generates input IDs: `table-save`, `table-revert`, `table-table`, etc.
- Server calls: `mod_table_server("table", ...)`
- Matching IDs in `input$save`, `input$revert`, `input$table`

## Table Module: Server

### Server Function Signature

```r
mod_table_server <- function(id, store_reactive, store_trigger) {
  shiny::moduleServer(id, function(input, output, session) {
    # ... implementation ...
  })
}
```

**Parameters:**
- `id`: Module namespace (must match UI)
- `store_reactive`: Reactive value containing DataStore R6 object
- `store_trigger`: Reactive value for manual invalidation

### Reactive Table Data

```r
table_data <- shiny::reactive({
  store_trigger()           # Explicit dependency
  store <- store_reactive() # Read R6 object
  
  if (is.null(store$data)) {
    return(data.frame())
  }
  
  store$data
})
```

**Flow:**
1. Whenever `store_trigger()` changes, reactive recomputes
2. Reads current `store` from `store_reactive()`
3. Returns `store$data` (the working, mutable copy)

### Widget Rendering

```r
output$table <- renderHotwidget({
  data <- table_data()
  if (nrow(data) == 0) {
    return(hotwidget(data = data.frame(Message = "No data loaded")))
  }
  hotwidget(data = data)
})
```

**Behavior:**
- Depends on `table_data()` reactive
- Rerenders whenever table_data changes
- Passes data frame directly to htmlwidget

## Action Buttons and State

### Initial State

```r
# Disable save/revert buttons initially (no modifications)
shinyjs::disable("save")
shinyjs::disable("revert")
```

### Enable on Modification

```r
store_reactive()$update_cell(...)
store_trigger(store_trigger() + 1)

shinyjs::enable("save")
shinyjs::enable("revert")

message("Cell updated: Row ", r_row, ", Col '", edit$col, "', Value: ", edit$value)
```

### Disable After Save/Revert

```r
# After successful save
shinyjs::disable("save")
shinyjs::disable("revert")

# After successful revert
shinyjs::disable("save")
shinyjs::disable("revert")
```

## User Notifications

### Success Notification

```r
awn::notify(
  "Changes saved to DuckDB successfully",
  type = "success"
)
```

### Error Notification

```r
awn::notify(
  paste("Update failed:", clean_error_message(error_msg)),
  type = "alert"
)
```

### Modal Dialog (Confirmation)

```r
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
```

## Summary Metrics Display

```r
output$summary_rows <- renderText({
  store_trigger()          # Explicit dependency
  store <- store_reactive()
  summary <- store$summary()
  as.character(summary$rows)
})

output$summary_cols <- renderText({
  store_trigger()
  store <- store_reactive()
  summary <- store$summary()
  as.character(summary$cols)
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

**Pattern:**
- Each output explicitly depends on `store_trigger()`
- Reads current store state
- Calls `$summary()` method
- Formats output (numeric formatting with %.1f)

## CSS Customization

### Card Styling

```css
.card-panel {
  background: white;
  border: 1px solid #dee2e6;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  padding: 1.5rem;
  margin-bottom: 1.5rem;
}

.summary-panel {
  background: white;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  border: 1px solid #dee2e6;
  border-radius: 8px;
  padding: 1.5rem;
}
```

### Summary Metrics

```css
.summary-metric {
  background: #f5f5f7;
  border-radius: 6px;
  padding: 1rem;
  margin-bottom: 1rem;
  text-align: center;
  border: 1px solid #e9ecef;
  transition: transform 0.2s, box-shadow 0.2s;
}

.summary-metric:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.summary-metric-value {
  font-size: 2rem;
  font-weight: 700;
  color: #2c3e50;
}

.summary-metric-value.highlight {
  color: #007bff;  /* MPG, HP */
}

.summary-metric-value.warning {
  color: #dc3545;  /* Modified count */
}
```

### Action Buttons

```css
.action-buttons {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid #e9ecef;
}

.btn {
  font-weight: 500;
  border-radius: 6px;
  padding: 0.5rem 1.25rem;
  transition: all 0.2s;
}

.btn-outline-danger {
  background-color: white;
  border-color: white;
}

.btn-outline-secondary {
  background-color: white;
  border-color: white;
}
```

## Loading Skeleton

```r
skeleton_replacement_script("table")
skeleton_content("table")
```

**Purpose:**
- Shows loading placeholder while app starts
- Replaced by actual content once JS loads
- Improves perceived performance

## Layout Principles

1. **Responsive Grid**: `layout_columns(col_widths = c(10, 2))` creates 10:2 ratio
2. **Card-Based**: Bootstrap cards for visual separation
3. **Namespace Isolation**: All IDs under module namespace
4. **Explicit Dependencies**: Reactive outputs explicitly depend on triggers
5. **Accessibility**: Icon labels, semantic HTML, ARIA support

## Key Differences from Raw Bootstrap

- **bslib**: Programmatic Bootstrap 5 theming
- **Modules**: Encapsulation prevents ID conflicts
- **Reactives**: Shiny handling, not manual DOM manipulation
- **Cards**: Semantic card containers with headers/footers
- **Navigation**: Page-based via nav_panel (not manual tabs)

## Summary

The UI architecture prioritizes:
- **Modularity**: Encapsulated, reusable components
- **Clarity**: Explicit dependencies via reactives and triggers
- **Safety**: Namespace isolation, no global selectors
- **Polish**: Bootstrap 5 theming, smooth transitions, clear feedback

Key principle: **UI follows data; data changes drive UI updates, never the reverse.**
