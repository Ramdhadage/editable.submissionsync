# HTMLWidget Communication Domain

## Overview

The htmlwidget layer provides **bidirectional JavaScript-R communication** for the table editing UI. It wraps the **Handsontable JavaScript library** and manages real-time cell edits through Shiny's input binding system.

## Widget Definition (R/hotwidget.R)

### Widget Creation

```r
hotwidget <- function(data, width = NULL, height = NULL, elementId = NULL) {
  
  if (missing(data) || is.null(data)) {
    stop("'data' parameter is required")
  }
  
  if (!is.data.frame(data)) {
    stop("'data' must be a data.frame")
  }
  
  # Calculate column widths based on type
  col_widths <- sapply(data, function(col) {
    if (is.numeric(col)) {
      100
    } else if (is.logical(col)) {
      80  
    } else {
      150
    }
  })
  
  x = list(
    data = data,
    colHeaders = as.list(names(data)),
    colTypes = as.list(sapply(data, function(col) class(col)[1], USE.NAMES = FALSE)),
    colWidths = as.list(col_widths),
    stretchH = "all",
    autoRowSize = FALSE,
    rowHeights = 30
  )
  
  htmlwidgets::createWidget(
    name = 'hotwidget',
    x,
    width = width,
    height = height,
    package = 'editable',
    elementId = elementId
  )
}
```

**Key Features:**
- R6-style object creation
- Data validation (required, must be data.frame)
- Column width calculation based on type
- Metadata passed to JS: headers, types, widths
- Stretch horizontally, fixed row height (30px)

### Shiny Integration

```r
hotwidgetOutput <- function(outputId, width = '100%', height = '400px'){
  htmlwidgets::shinyWidgetOutput(
    outputId, 
    'hotwidget', 
    width, 
    height, 
    package = 'editable'
  )
}

renderHotwidget <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) { expr <- substitute(expr) }
  htmlwidgets::shinyRenderWidget(expr, hotwidgetOutput, env, quoted = TRUE)
}
```

**Usage in Module:**
```r
output$table <- renderHotwidget({
  data <- table_data()
  hotwidget(data = data)
})

hotwidgetOutput(ns("table"), height = "500px")
```

## JavaScript Implementation (inst/htmlwidgets/hotwidget.js)

### Widget Factory

```javascript
HTMLWidgets.widget({
  name: 'hotwidget',
  type: 'output',
  
  factory: function(el, width, height) {
    let hotInstance = null;
    let currentData = null;
    let isUpdating = false;
    
    return {
      renderValue: function(x) { ... },
      resize: function(width, height) { ... }
    };
  }
});
```

**Structure:**
- `factory()` creates the widget instance
- `renderValue()`: Render when data changes
- `resize()`: Handle window resize events

### Data Transformation

```javascript
renderValue: function(x) {
  currentData = HTMLWidgets.dataframeToD3(x.data);
  const originalColHeaders = x.colHeaders || Object.keys(currentData[0] || {});
  const colHeaders = originalColHeaders.map((header) => header.toUpperCase());
  const colTypes = x.colTypes || {};
  
  if (hotInstance) {
    hotInstance.destroy();
    hotInstance = null;
  }
  el.innerText = "";
  
  const colWidths = x.colWidths || null;
  const rowHeights = x.rowHeights || 'auto';
  
  // Initialize Handsontable
  hotInstance = new Handsontable(el, { ... });
}
```

**Key Points:**
- `HTMLWidgets.dataframeToD3()`: Convert R data frame to JavaScript array
- Column headers uppercase for display
- Destroy and recreate on re-render (ensures clean state)
- Clear element before rendering

### Handsontable Configuration

```javascript
hotInstance = new Handsontable(el, {
  themeName: 'ht-theme-main',
  data: currentData,
  colHeaders: colHeaders,
  className: 'htCenter',
  rowHeaders: false,
  columnSorting: true,
  filters: true,
  dropdownMenu: true,
  manualColumnResize: true,
  contextMenu: true,
  search: true,
  stretchH: 'all',
  colWidths: colWidths,
  rowHeights: rowHeights,
  autoRowSize: false,
  pagination: {
    pageSize: 50,
    pageSizeList: ['auto', 5, 10, 20, 50, 100],
    initialPage: 1,
    showPageSize: true,
    showCounter: true,
    showNavigation: true,
  },
  
  columns: originalColHeaders.map((colName) => {
    const colType = colTypes[colName];
    const config = { data: colName };
    
    // Read-only MODEL column
    if (colName === 'MODEL') {
      config.readOnly = true;
    }
    
    // Type-specific configuration
    switch(colType) {
      case 'numeric':
        config.type = 'numeric';
        config.numericFormat = { pattern: '0,0.00' };
        break;
      case 'integer':
        config.type = 'numeric';
        config.numericFormat = { pattern: '0,0' };
        break;
      case 'character':
        config.type = 'text';
        break;
      case 'logical':
        config.type = 'checkbox';
        break;
      case 'factor':
        config.type = 'select';
        config.selectOptions = [...new Set(x.data[colName])];
        break;
      default:
        config.type = 'text';
    }
    return config;
  }),
  
  // Hooks and license
  afterChange: function(changes, source) { ... },
  afterValidate: function(isValid, value, row, prop, source) { ... },
  licenseKey: 'non-commercial-and-evaluation',
})
```

**Configuration:**
- Theme: `ht-theme-main` (Handsontable's main theme)
- Sorting, filtering, dropdown menus enabled
- Pagination: 50 rows default, adjustable
- Column-level type validation
- Row headers hidden
- Manual column resize enabled
- Context menu (right-click) enabled

### Edit Capture: afterChange Hook

```javascript
afterChange: function(changes, source) {
  // Ignore loadData events and updates from R
  if (source === 'loadData' || isUpdating) {
    return;
  }
  
  // Only capture user edits
  if (source !== 'edit' || !changes) {
    return;
  }
  
  // Get first change (single-cell edit pattern)
  const change = changes[0];
  const [row, prop, oldValue, newValue] = change;
  
  // Ignore no-op edits
  if (oldValue === newValue) {
    return;
  }
  
  // Send to R via Shiny input binding
  if (typeof Shiny !== 'undefined') {
    Shiny.setInputValue(el.id + '_edit', {
      row: row,                    // 0-based index
      col: prop,                   // Column name
      oldValue: oldValue,          // Previous value
      value: newValue,             // New value
      timestamp: Date.now()        // When edit occurred
    });
  }
}
```

**Key Points:**
- Filters on `source === 'edit'` (user edits only)
- Ignores loadData events (R rendering)
- Ignores isUpdating events (R forcing redraw)
- Single-cell edit pattern: processes only first change
- Sends 0-based row index (JavaScript convention)
- Sends column by name (not index)

### Validation Hook: afterValidate

```javascript
afterValidate: function(isValid, value, row, prop, source) {
  if (!isValid && source === 'edit') {
    console.warn('Validation failed:', {row, col: prop, value});
  }
}
```

**Purpose:**
- Logs validation failures (client-side)
- Warning only; doesn't prevent edit in JS
- R-layer does true validation and rejection

## Communication Flow

### R → JavaScript (Re-render)

```
reactiveVal(data) changes
  ↓
output$table <- renderHotwidget()
  ↓
hotwidget(data = new_data)  [R function]
  ↓
HTMLWidgets.createWidget() + session$sendCustomMessage()
  ↓
JavaScript: renderValue(x)
  ↓
HTMLWidgets.dataframeToD3() [Convert R data frame]
  ↓
hotInstance.destroy() + hotInstance = new Handsontable()
  ↓
Table re-rendered with updated data
```

### JavaScript → R (Edit Event)

```
User edits cell in Handsontable
  ↓
JS: afterChange hook fires
  ↓
JS: Shiny.setInputValue('table-table_edit', {row, col, value})
  ↓
R: observeEvent(input$table_edit)
  ↓
R: store$update_cell(row + 1, col, value)  [Convert 0-based to 1-based]
  ↓
R: store_trigger(...)  [Force invalidation]
  ↓
R: renderHotwidget() [Re-render]
  ↓
JS: renderValue(x)  [Receive updated data]
  ↓
Table re-rendered (successful edit visible)
```

OR on error:

```
R validation fails
  ↓
R: awn::notify("error message", type = "alert")
  ↓
R: store_trigger(...)  [Still force invalidation]
  ↓
R: renderHotwidget()  [Re-render with reverted data]
  ↓
User sees original value (edit was rejected)
```

## Edit Debouncing: RAF Pattern

The module uses `requestAnimationFrame` (RAF) to batch rapid edits:

```r
shiny::observeEvent(input$table_edit, {
  edit <- input$table_edit
  
  # Queue the edit
  edit_batch(edit)
  
  # Clear existing timer
  if (!is.null(edit_timer())) {
    timer_id <- edit_timer()
    shinyjs::runjs(sprintf("clearTimeout(%d)", timer_id))
  }
  
  # Schedule processing via RAF
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
  
  # Process the batched edit
  store_reactive()$update_cell(row = edit$row + 1, col = edit$col, value = edit$value)
  store_trigger(store_trigger() + 1)
})
```

**Benefits:**
- Prevents edit storms (multiple rapid keystrokes = single R update)
- RAF waits for next animation frame = natural batching window
- Reduces server load for fast typers

## Index Conversion

JavaScript uses 0-based row indexing; R uses 1-based:

```r
# JavaScript sends row 0 (first row)
edit$row === 0

# R converts to 1-based
r_row <- edit$row + 1  # 1

# Update R6 object (1-based)
store_reactive()$update_cell(row = r_row, col = edit$col, value = edit$value)
```

**Column indexing:**
- JavaScript: Uses column name (string), not index
- R: Accepts column name (string) or index (1-based integer)
- No conversion needed for columns

## Type Handling in JavaScript

Handsontable enforces client-side validation:

```javascript
columns: originalColHeaders.map((colName) => {
  const config = { data: colName };
  
  switch(colType) {
    case 'numeric':
      config.type = 'numeric';
      config.numericFormat = { pattern: '0,0.00' };  // Display format
      break;
      
    case 'logical':
      config.type = 'checkbox';  // Boolean checkbox input
      break;
      
    case 'factor':
      config.type = 'select';
      config.selectOptions = [...new Set(x.data[colName])];  // Dropdown
      break;
      
    default:
      config.type = 'text';
  }
  
  return config;
})
```

**Note:** JavaScript validation is UX-only. True validation happens in R via `validate_no_na_loss()`.

## Pagination

Large datasets paginated in Handsontable:

```javascript
pagination: {
  pageSize: 50,                          // 50 rows per page default
  pageSizeList: ['auto', 5, 10, 20, 50, 100],  // Options
  initialPage: 1,
  showPageSize: true,                    // Show page size selector
  showCounter: true,                     // Show "Row X of Y"
  showNavigation: true,                  // Show nav buttons
}
```

**Benefits:**
- Only 50 rows rendered in DOM
- Faster rendering for 100K+ row datasets
- User can adjust page size

## CSS Integration

```css
.hotwidget {
  border: 1px solid #dee2e6;
  border-radius: 6px;
  position: relative;
  overflow: visible;
}

.hotwidget .handsontable {
  --ht-cell-horizontal-border-color: transparent;
  --ht-cell-vertical-border-color: #dee2e6;
  --ht-border-color: #dee2e6;
}

.hotwidget .htFiltersMenuLabel,
.hotwidget .htFiltersMenuCondition,
.hotwidget .handsontable-dropdown {
  z-index: 1000 !important;
}

.hotwidget .handsontable tbody tr td:first-child {
  border-left: 1px solid #dee2e6 !important;
}
```

**Purpose:**
- Borders and spacing
- Z-index for dropdown menus
- Theme customization

## Summary

The htmlwidget communication layer:
- **Encapsulates** Handsontable complexity
- **Bridges** JavaScript and R seamlessly
- **Validates** at both client (UX) and server (safety) layers
- **Batches** rapid edits for efficiency
- **Handles** type conversions and index mismatches
- **Provides** rich UI with sorting, filtering, pagination

Key principle: **JavaScript handles UI/UX; R handles data integrity.**
