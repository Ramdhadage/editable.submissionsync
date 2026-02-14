#' Handsontable Interactive Table Widget
#'
#' @description
#' Custom htmlwidget wrapping Handsontable library for editable data tables.
#' Implements bidirectional R ↔ JS communication with single-cell edit validation.
#'
#' @details
#' This widget is designed for production Shiny applications requiring:
#' - Deterministic single-cell edits (no batch operations)
#' - Type validation in both JS and R layers
#' - Controlled reactivity through explicit state management
#' - Clean separation between UI (Handsontable) and state (R6)
#'
#' @param data Data frame to display and edit. Required.
#' @param width Widget width (CSS unit or NULL for auto)
#' @param height Widget height (CSS unit or NULL for auto)
#' @param elementId Explicit element ID for Shiny input binding (auto-generated if NULL)
#'
#' @return htmlwidget object
#'
#' @section JavaScript Communication:
#' The widget sends edit events to Shiny via `input$<id>_edit`:
#' ```
#' {
#'   row: 0,              # 0-based JavaScript index
#'   col: "mpg",          # Column name
#'   oldValue: 21.0,      # Previous value
#'   value: 22.5          # New value (user input)
#' }
#' ```
#'
#' @examples
#' \dontrun{
#' # Standalone usage
#' hotwidget(data = mtcars)
#'
#' # In Shiny
#' output$table <- renderHotwidget({
#'   hotwidget(data = store$data)
#' })
#' }
#'
#' @import htmlwidgets
#' @export
hotwidget <- function(data, width = NULL, height = NULL, elementId = NULL) {

  if (missing(data) || is.null(data)) {
    stop("'data' parameter is required")
  }

  if (!is.data.frame(data)) {
    stop("'data' must be a data.frame")
  }

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

  # create widget
  htmlwidgets::createWidget(
    name = 'hotwidget',
    x,
    width = width,
    height = height,
    package = 'editable',
    elementId = elementId
  )
}

#' Shiny bindings for hotwidget
#'
#' Output and render functions for using hotwidget within Shiny
#' applications and interactive Rmd documents.
#'
#' @param outputId output variable to read from
#' @param width,height Must be a valid CSS unit (like \code{'100\%'},
#'   \code{'400px'}, \code{'auto'}) or a number, which will be coerced to a
#'   string and have \code{'px'} appended.
#' @param expr An expression that generates a hotwidget
#' @param env The environment in which to evaluate \code{expr}.
#' @param quoted Is \code{expr} a quoted expression (with \code{quote()})? This
#'   is useful if you want to save an expression in a variable.
#'
#' @name hotwidget-shiny
#'
#' @export
hotwidgetOutput <- function(outputId, width = '100%', height = '400px'){
  htmlwidgets::shinyWidgetOutput(outputId, 'hotwidget', width, height, package = 'editable')
}

#' @rdname hotwidget-shiny
#' @export
renderHotwidget <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) { expr <- substitute(expr) } # force quoted
  htmlwidgets::shinyRenderWidget(expr, hotwidgetOutput, env, quoted = TRUE)
}
