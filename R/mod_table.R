#' Table Module UI
#'
#' @description
#' Shiny module UI for interactive data table with Handsontable widget.
#' Displays editable table, revert button, and live summary statistics.
#'
#' @param id Character string. Module namespace ID.
#'
#' @return tagList of UI components
#'
#' @examples
#' \dontrun{
#' mod_table_ui("table")
#' }
#'
#' @export
mod_table_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shinyjs::useShinyjs(),
    awn::useAwn(),
    golem_add_external_resources(),
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

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Columns"),
            div(class = "summary-metric-value", textOutput(ns("summary_cols"), inline = TRUE))
          ),

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Average MPG"),
            div(class = "summary-metric-value highlight", textOutput(ns("summary_mpg"), inline = TRUE))
          ),

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Average HP"),
            div(class = "summary-metric-value highlight", textOutput(ns("summary_hp"), inline = TRUE))
          ),

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Modified"),
            div(class = "summary-metric-value warning", textOutput(ns("summary_modified"), inline = TRUE)),
            div(class = "text-muted small mt-1", "cells")
          )
        )
      )
    )
  )
}
#' Table Module Server
#'
#' @description
#' Shiny module server implementing reactive data table with R6 state management.
#' Demonstrates production-grade patterns:
#' - reactiveVal() wrapping R6 for explicit invalidation
#' - Controlled reactivity with manual triggers
#' - Bidirectional JS ↔ R communication
#' - Type-safe cell updates through R6 validation
#'
#' @param id Character string. Module namespace ID (must match UI).
#' @param store_reactive Reactive value containing DataStore R6 object.
#'   Pattern: store_reactive <- reactiveVal(DataStore$new())
#' @param store_trigger Reactive value used to force invalidation.
#'   Pattern: store_trigger <- reactiveVal(0)
#'
#' @return Module server function (for testServer compatibility)
#'
#' @section Reactivity Pattern:
#' This module uses explicit invalidation via reactiveVal():
#' ```r
#' # Reading: triggers reactive dependency
#' current_store <- store_reactive()
#'
#' # Writing: triggers invalidation
#' store_reactive()$update_cell(row, col, value)
#' store_trigger(store_trigger() + 1)  # Force invalidation
#' ```
#'
#' @examples
#' \dontrun{
#' # In app_server.R:
#' store <- DataStore$new()
#' store_reactive <- reactiveVal(store)
#' store_trigger <- reactiveVal(0)
#' mod_table_server("table", store_reactive, store_trigger)
#' }
#'
#' @export
mod_table_server <- function(id, store_reactive, store_trigger) {
  shiny::moduleServer(id, function(input, output, session) {

    shinyjs::disable("save")
    shinyjs::disable("revert")

    table_data <- shiny::reactive({
      store_trigger()
      store <- store_reactive()  #

      if (is.null(store$data)) {
        return(data.frame())
      }

      store$data
    })

    output$table <- renderHotwidget({
      data <- table_data()
      if (nrow(data) == 0) {
        return(hotwidget(data = data.frame(Message = "No data loaded")))
      }
      hotwidget(data = data)
    })
    edit_batch <- reactiveVal(NULL)
    edit_timer <- reactiveVal(NULL)

    shiny::observeEvent(input$table_edit, {
      edit <- input$table_edit

      if (is.null(edit$row) || is.null(edit$col) || is.null(edit$value)) {
        warning("Invalid edit received from widget: missing row/col/value")
        return()
      }

      edit_batch(edit)

      if (!is.null(edit_timer())) {
        timer_id <- edit_timer()
        shinyjs::runjs(sprintf("clearTimeout(%d)", timer_id))
      }

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
        r_row <- edit$row + 1

        store_reactive()$update_cell(
          row = r_row,
          col = edit$col,
          value = edit$value
        )

        store_trigger(store_trigger() + 1)

        shinyjs::enable("save")
        shinyjs::enable("revert")

        message("Cell updated: Row ", r_row, ", Col '", edit$col, "', Value: ", edit$value)

      }, error = function(e) {
        error_msg <- conditionMessage(e)
        clean_msg <- clean_error_message(error_msg)
        awn::notify(
          paste("Update failed:", clean_error_message(error_msg)),
          type = "alert"
        )

        store_trigger(store_trigger() + 1)
      })
      edit_batch(NULL)
      edit_timer(NULL)
    })

    shiny::observeEvent(input$save, {
      modified_count <- store_reactive()$get_modified_count()

      shiny::showModal(
        shiny::modalDialog(
          title = "Confirm Save to Database",
          shiny::p(
            "You are about to save your changes to the DuckDB database."
          ),
          shiny::p(
            shiny::strong("Important:"),
            " Saved changes will become the new baseline and cannot be reverted."
          ),
          shiny::p(
            sprintf("Modified cells: %d", modified_count)
          ),
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
        error_msg <- conditionMessage(e)
        clean_msg <- clean_error_message(error_msg)
        awn::notify(
          paste("Save failed:", conditionMessage(e)),
          type = "alert"
        )
      })
    })

    shiny::observeEvent(input$revert, {
      tryCatch({
        store_reactive()$revert()

        store_trigger(store_trigger() + 1)

        shinyjs::disable("save")
        shinyjs::disable("revert")

        awn::notify(
          "Data reverted to original state",
          type = "success"
        )

      }, error = function(e) {
        error_msg <- conditionMessage(e)
        clean_msg <- clean_error_message(error_msg)
        awn::notify(
          paste("Revert failed:", conditionMessage(e)),
          type = "error")
      })
    })

    output$summary_rows <- renderText({
      store_trigger()
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

    output$summary_hp <- renderText({
      store_trigger()
      store <- store_reactive()
      summary <- store$summary()
      if (!is.null(summary$numeric_means) && "hp" %in% names(summary$numeric_means)) {
        sprintf("%.1f", summary$numeric_means["hp"])
      } else {
        "N/A"
      }
    })

    output$summary_modified <- renderText({
      store_trigger()
      store <- store_reactive()
      as.character(store$get_modified_count())
    })
  })
}
