# Custom HTMLWidgets Style Guide

## Overview

Custom htmlwidgets in editable provide bidirectional R ↔ JavaScript communication for table editing. The widget consists of:
1. **R Wrapper** (`R/hotwidget.R`): Renders widget, manages parameters
2. **JavaScript Factory** (`inst/htmlwidgets/hotwidget.js`): Initializes Handsontable, handles events
3. **YAML Manifest** (`inst/htmlwidgets/hotwidget.yaml`): Widget metadata and dependency registration

## File Convention

**Files:**
- `R/{widgetname}.R` — R wrapper function
- `inst/htmlwidgets/{widgetname}.js` — JavaScript factory
- `inst/htmlwidgets/{widgetname}.yaml` — Metadata

**Naming:**
- Widget name: lowercase, no underscores
- R function: `{widgetname}()` for constructor
- Shiny binding: `{widgetname}_output()`, `render_{widgetname}()`

## R Wrapper Pattern

### Basic Structure

```r
#' Create Handsontable Editable Table Widget
#'
#' @description
#' Wraps Handsontable JavaScript library for interactive table editing.
#' Handles data display, cell editing, column type validation.
#'
#' @param data data.frame. Table data to display.
#' @param colTypes Character vector. Column types: "text", "numeric", "date", "checkbox".
#'   Default: auto-detect from data.
#' @param rowHeaders Logical. Show row numbers? Default: TRUE.
#' @param colHeaders Logical. Show column headers? Default: TRUE.
#' @param readOnly Logical. Disable editing? Default: FALSE.
#' @param... Additional parameters passed to htmlwidgets::createWidget().
#'
#' @return Widget object of class htmlwidget subtypes c("hotwidget", "htmlwidget").
#'
#' @examples
#' \dontrun{
#' hotwidget(mtcars, colTypes = c("text", rep("numeric", 10)))
#' }
#'
#' @export
hotwidget <- function(
    data,
    colTypes = NULL,
    rowHeaders = TRUE,
    colHeaders = TRUE,
    readOnly = FALSE,
    ...) {
  
  # Input validation (deterministic phase)
  checkmate::assert_data_frame(data, null.ok = FALSE)
  checkmate::assert_logical(rowHeaders, len = 1, null.ok = FALSE)
  checkmate::assert_logical(colHeaders, len = 1, null.ok = FALSE)
  checkmate::assert_logical(readOnly, len = 1, null.ok = FALSE)
  
  # Auto-detect column types if not provided
  if (is.null(colTypes)) {
    colTypes <- detect_column_types(data)
  }
  
  # Prepare widget parameters (domain logic)
  x <- list(
    data = data,
    colTypes = colTypes,
    rowHeaders = rowHeaders,
    colHeaders = colHeaders,
    readOnly = readOnly,
    # Widget configuration
    stretchH = "all",           # Column width management
    colWidthDropdown = TRUE,
    contextMenu = list(         # Right-click menu
      "row_above", "row_below", "col_left", "col_right"
    ),
    pagination = list(          # Pagination config
      enabled = TRUE,
      pageSize = 50
    ),
    filters = TRUE,             # Column filters
    columnSorting = list(       # Sorting
      indicator = TRUE
    )
  )
  
  # Create htmlwidget with dependencies
  htmlwidgets::createWidget(
    name = "hotwidget",
    x = x,
    width = NULL,
    height = NULL,
    package = "editable",
    ...
  )
}

#' widget_html_dependency
#'
#' @description
#' Register htmlwidget dependencies (CSS, JavaScript libraries).
#' Called automatically by htmlwidgets rendering pipeline.
#'
#' @keywords internal
widget_html_dependency <- function() {
  # Dependencies are defined in hotwidget.yaml
  # This function documented for completeness
  list()
}
```

**Pattern:**
- Constructor function with clear R naming
- Input validation before JS call
- List of parameters as `x` (transmitted to JS)
- Return `htmlwidgets::createWidget()` for proper class structure
- Document @export if user-facing

### Shiny Integration

```r
#' Shiny Bindings for hotwidget
#'
#' @description
#' Output and render functions for use in Shiny apps.
#'
#' @param outputId Character. Output variable to read from.
#' @param width Character. CSS width (e.g., "100%").
#' @param height Character. CSS height (e.g., "400px").
#' @param expr Expression producing hotwidget object.
#' @param env Environment where expr should be evaluated.
#' @param quoted Logical. Is expr quoted? (Advanced)
#'
#' @name hotwidget-shiny
#'
#' @keywords internal
NULL

#' @rdname hotwidget-shiny
#' @export
hotwidget_output <- function(outputId, width = "100%", height = "400px") {
  htmlwidgets::shinyWidgetOutput(outputId, "hotwidget", width, height, class = "hotwidget-container")
}

#' @rdname hotwidget-shiny
#' @export
render_hotwidget <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(expr, hotwidget_output, env, quoted = TRUE)
}
```

**Pattern:**
- Output function: wraps data and display configuration
- Render function: links module server to widget
- Use `htmlwidgets::shinyWidgetOutput()` for input binding
- Use `htmlwidgets::shinyRenderWidget()` for render integration
- Both exported for use in Shiny modules

### Helper Functions

```r
#' Detect Column Types from Data
#'
#' @description
#' Maps R data types to Handsontable column types.
#' Used for auto-detection if colTypes not specified.
#'
#' @param data data.frame. Data to analyze.
#'
#' @return Character vector of Handsontable types.
#'
#' @keywords internal
detect_column_types <- function(data) {
  sapply(data, function(x) {
    if (is.numeric(x)) {
      "numeric"
    } else if (is.logical(x)) {
      "checkbox"
    } else if (inherits(x, "Date")) {
      "date"
    } else {
      "text"
    }
  }, simplify = TRUE, USE.NAMES = FALSE)
}
```

## JavaScript Factory Pattern

### Manifest (YAML)

```yaml
# inst/htmlwidgets/hotwidget.yaml
name: hotwidget
version: 1.0.0
title: Handsontable Editable Table Widget

script:
  - libs/handsontable/handsontable.full.min.js
  - libs/numbro-2.3.2/js/numbro.min.js
  - hotwidget.js

stylesheet:
  - libs/handsontable/handsontable.min.css
  - libs/handsontable/ht-theme-main.css

dependencies: []  # No external R package deps
```

**Rules:**
- `script` and `stylesheet` relative paths from `inst/htmlwidgets/`
- List relative URLs (not absolute)
- Script order matters (dependencies first)
- Dependencies section for R packages

### Widget Factory

```javascript
// inst/htmlwidgets/hotwidget.js

// Factory function (required by htmlwidgets)
HTMLWidgets.widget({
  name: "hotwidget",
  type: "output",
  
  factory: function(el, width, height) {
    // Closure scope for this widget instance
    var instance = {
      data: null,
      container: null,
      hot: null,
      editQueue: []
    };
    
    return {
      // Render function: called when widget created/updated
      renderValue: function(x) {
        // Clear previous widget
        if (instance.hot) {
          instance.hot.destroy();
        }
        
        // Initialize Handsontable with x parameters
        instance.renderValue(x, el, width, height);
      },
      
      // Resize function: called on window resize
      resize: function(w, h) {
        if (instance.hot) {
          instance.hot.updateSettings({
            height: h
          });
        }
      },
      
      // Public instance API
      instance: instance
    };
  }
});

// Separate rendering logic for readability
HTMLWidgets.widget({
  name: "hotwidget",
  type: "output",
  
  factory: function(el, width, height) {
    return {
      renderValue: function(x) {
        // 1. Prepare DOM structure
        var container = document.createElement("div");
        container.className = "hotwidget-container";
        container.style.width = width || "100%";
        container.style.height = height || "100%";
        el.appendChild(container);
        
        // 2. Handsontable initialization
        var hot = new Handsontable(container, {
          // Data
          data: x.data,
          colHeaders: x.colHeaders,
          rowHeaders: x.rowHeaders,
          
          // Appearance
          stretchH: x.stretchH || "all",
          theming: true,
          
          // Editing
          allowInvalid: false,  // Block invalid cell edits
          editor: "text",
          
          // Validation
          cells: function(row, col) {
            // Column type → validation rules
            var colType = x.colTypes[col];
            
            var cellProps = {};
            
            if (colType === "numeric" || colType === "integer") {
              cellProps.type = "numeric";
              cellProps.numericFormat = {
                pattern: "$0,0.00"
              };
            } else if (colType === "checkbox") {
              cellProps.type = "checkbox";
            } else if (colType === "date") {
              cellProps.type = "date";
              cellProps.dateFormat = "YYYY-MM-DD";
            } else {
              cellProps.type = "text";
            }
            
            return cellProps;
          },
          
          // Filtering & sorting
          filters: x.filters !== false,
          columnSorting: x.columnSorting || { indicator: true },
          
          // Context menu
          contextMenu: x.contextMenu || false,
          
          // Menu items customization
          contextMenu: {
            items: {
              row_above: {},
              row_below: {},
              col_left: {},
              col_right: {}
            }
          },
          
          // Pagination
          pagination: x.pagination,
          
          // Event handlers
          afterChange: handleEdit,     // User edits cell
          afterColumnResize: handleResize
        });
        
        // 3. Store references
        instance.hot = hot;
        instance.data = x.data;
        instance.container = container;
        
        // 4. Set up edit queue with RAF debouncing
        instance.editHandler = handleEdit.bind(null, hot, x);
      }
    };
  }
});
```

**Pattern:**
- Widget name matches R function name
- `factory` function receives `el`, `width`, `height`
- Returns object with `renderValue(x)` and `resize(w, h)` methods
- `x` contains parameters from R
- Store instance data in closure scope

### Edit Event Handling

```javascript
// Edit handler with RAF debouncing
var edits = {};
var editScheduled = false;

function handleEdit(hot, config, changes) {
  if (!changes || changes.length === 0) return;
  
  // Collect edits instead of sending immediately
  changes.forEach(function(change) {
    var row = change[0];
    var col = change[1];
    var newValue = change[3];
    
    edits[row + "_" + col] = {
      row: row + 1,               // Convert 0-based to 1-based for R
      col: col + 1,
      value: newValue
    };
  });
  
  // Schedule Shiny update with RAF
  if (!editScheduled) {
    editScheduled = true;
    
    requestAnimationFrame(function() {
      // Batch all pending edits
      var batch = Object.values(edits);
      
      if (batch.length > 0) {
        // Send to Shiny via input binding
        Shiny.setInputValue("hotwidget_edits", batch, {
          priority: "event"
        });
      }
      
      edits = {};
      editScheduled = false;
    });
  }
}
```

**Pattern:**
- Collect edits in RAF frame
- Convert 0-based JS indices to 1-based R indices
- Batch edits before sending to Shiny
- Use `Shiny.setInputValue()` for communication
- Clear queue after transmission

### Input Binding (Shiny Integration)

```javascript
// Register custom Shiny input binding
var hotwidgetInputBinding = new Shiny.InputBinding();

$.extend(hotwidgetInputBinding, {
  find: function(scope) {
    return $(scope).find(".hotwidget-container");
  },
  
  getId: function(el) {
    return el.id || null;
  },
  
  getValue: function(el) {
    return $(el).data("hotwidget");
  },
  
  subscribe: function(el, callback) {
    // Listen for edit events
    $(el).on("hotwidget.edit", function(e, data) {
      callback(data);
    });
  },
  
  unsubscribe: function(el) {
    $(el).off("hotwidget.edit");
  }
});

Shiny.inputBindings.register(hotwidgetInputBinding, "hotwidget.hotwidgetInputBinding");
```

**Pattern:**
- Implement Shiny InputBinding interface
- `find()` locates widget elements in DOM
- `getValue()` returns current value
- `subscribe()` registers event listener
- `unsubscribe()` cleans up

## Type Validation Integration

```javascript
// Column type → validation function mapping
var validators = {
  "numeric": function(value) {
    if (value === null || value === "") return true;  // Allow empty
    return !isNaN(parseFloat(value));
  },
  
  "integer": function(value) {
    if (value === null || value === "") return true;
    var num = parseInt(value);
    return !isNaN(num) && String(num) === String(value);
  },
  
  "checkbox": function(value) {
    return value === true || value === false || value === null;
  },
  
  "date": function(value) {
    if (value === null || value === "") return true;
    return /^\d{4}-\d{2}-\d{2}$/.test(value);
  },
  
  "text": function(value) {
    return true;  // All values valid as text
  }
};

// Use in Handsontable config
cells: function(row, col) {
  var colType = x.colTypes[col];
  
  return {
    validator: validators[colType] || validators.text
  };
}
```

**Pattern:**
- Validators per column type
- Return true (valid) or false (invalid)
- Handsontable blocks invalid edits
- Empty cells treated specially

## Documentation Standards

```r
#' Create Handsontable Editable Table Widget
#'
#' @description
#' Wraps Handsontable JavaScript library for interactive table editing
#' in Shiny applications.
#'
#' @details
#' The widget provides:
#' - Cell editing with type validation
#' - Column filtering and sorting
#' - Pagination (50 rows/page default)
#' - Row and column context menus
#' - Numeric formatting with Numbro.js
#'
#' Edit events are batched and debounced via requestAnimationFrame
#' for performance.
#'
#' @return Widget object for use in Shiny UI.
#'
#' @examples
#' \dontrun{
#'   ui <- fluidPage(
#'     h1("Data Editor"),
#'     hotwidget_output("table", height = "500px")
#'   )
#'
#'   server <- function(input, output) {
#'     output$table <- render_hotwidget({
#'       hotwidget(mtcars)
#'     })
#'   }
#'
#'   shinyApp(ui, server)
#' }
#'
#' @export
hotwidget <- function(...) { }
```

**Rules:**
- Describe what widget does, not how JavaScript works
- @details: Features, performance characteristics, event batching
- Include Shiny integration example in @examples
- Document returned object type
- Mark @export if user-facing

## Summary

Custom htmlwidgets follow a three-layer pattern:

1. **R Wrapper** (R/hotwidget.R):
   - Input validation (deterministic)
   - Parameter collection in named list `x`
   - Return `htmlwidgets::createWidget()`
   - Shiny integration functions for modules

2. **JavaScript Factory** (inst/htmlwidgets/hotwidget.js):
   - `renderValue(x)`: Initialize from R parameters
   - `resize(w, h)`: Handle window resize
   - Event handlers with RAF debouncing
   - Shiny input binding for two-way communication

3. **Metadata** (inst/htmlwidgets/hotwidget.yaml):
   - Dependency registration
   - CSS/JS import order
   - External library versions

Key principle: **Maximum JavaScript isolation, minimum Shiny coupling.**
