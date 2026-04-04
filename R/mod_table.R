#' Table Module UI
#'
#' @description
#' Shiny module UI for interactive data table with Handsontable widget.
#' Displays editable table, revert button, and live summary statistics.
#'
#' @param id Character string. Module namespace ID.
#'
#' @return tagList of UI components
#' @import shinycssloaders golem
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
      ),
      actionButton(
        ns("submit"),
        "Submit for Review",
        icon = icon("paper-plane"),
        class = "btn btn-success",
        style = "margin-left: 1rem;"
      )
    ),

    # NEW: Status display
    div(
      class = "alert alert-info",
      id = ns("status_panel"),
      textOutput(ns("submission_status"))
    ),

    bslib::layout_columns(
      col_widths = c(10, 2),

      bslib::card(
        class = "card-panel",
        bslib::card_header("Data Table"),
        bslib::card_body(
          div(
            class = "hotwidget-container",
            withCustomSpinner(
              hotwidgetOutput(ns("table"), height = "500px"),
              min_height = "520px"
            )
          )
        )
      ),

      bslib::card(
        class = "summary-panel",
        bslib::card_header("Summary"),
        bslib::card_body(
          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Records"),
            div(
              class = "summary-metric-value",
              withCustomSpinner(
                textOutput(ns("summary_rows"), inline = TRUE),
                min_height = "50px"
              )
            )
          ),

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Columns"),
            div(class = "summary-metric-value", textOutput(ns("summary_cols"), inline = TRUE))
          ),

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Average AGE"),
            div(class = "summary-metric-value highlight", textOutput(ns("summary_age"), inline = TRUE))
          ),

          div(
            class = "summary-metric",
            div(class = "summary-metric-label", "Average BMIBL"),
            div(class = "summary-metric-value highlight", textOutput(ns("summary_bmibl"), inline = TRUE))
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
#' @param user_id Reactive. Current user ID (from authentication).
#' @param user_role Reactive. Current user role (Editor, Reviewer, Admin).
#' @param submission_service SubmissionService R6 object (for workflow).
#' @param con Reactive. DBI connection to adsl.duckdb.
#'
#' @return Module server function (for testServer compatibility)
#'
#' @examples
#' \dontrun{
#' # In app_server.R:
#' store <- DataStore$new()
#' store_reactive <- reactiveVal(store)
#' store_trigger <- reactiveVal(0)
#' mod_table_server("table", store_reactive, store_trigger,
#'                  user_id = reactive(1), user_role = reactive("Editor"),
#'                  submission_service = ss, con = reactive(con_obj))
#' }
#'
#' @export
mod_table_server <- function(id, store_reactive, store_trigger,
                             user_id = NULL, user_role = NULL,
                             submission_service = NULL, con = NULL) {
  shiny::moduleServer(id, function(input, output, session) {

    shinyjs::disable("save")
    shinyjs::disable("revert")
    column_summary_dependencies <- list(
      AGE = c("summary_age", "summary_rows"),
      BMIBL = c("summary_bmibl", "summary_rows"),
      SUBJID = c("summary_rows"),
      SITEID = c("summary_rows")
    )
    row_count_trigger <- reactiveVal(0)
    age_trigger <- reactiveVal(0)
    bmibl_trigger <- reactiveVal(0)
    modified_trigger <- reactiveVal(0)

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
      delta <- if (exists("last_delta_update", where = .GlobalEnv)) {
        .GlobalEnv$last_delta_update
      } else {
        NULL
      }

      if (!is.null(delta)) {
        result <- hotwidget(
          data = data,
          type = "delta",
          updatedCells = delta$updatedCells,
          modifiedCount = delta$modifiedCount,
          affectedColumns = delta$affectedColumns
        )
        rm("last_delta_update", envir = .GlobalEnv)
        return(result)
      }
      hotwidget(data = data)
    })
    edit_batch <- reactiveVal(list())
    edit_timer <- reactiveVal(NULL)

    shiny::observeEvent(input$table_edit, {
      edit <- input$table_edit

      if (is.null(edit$row) || is.null(edit$col) || is.null(edit$value)) {
        warning("Invalid edit received from widget: missing row/col/value")
        return()
      }

      current_batch <- edit_batch()
      if (!is.list(current_batch) || length(current_batch) == 0) {
        current_batch <- list()
      }
      batch_key <- paste0(edit$row, "_", edit$col)
      current_batch[[batch_key]] <- edit
      edit_batch(current_batch)

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
      batch <- edit_batch()

      if (is.null(batch) || length(batch) == 0) return()

      tryCatch({
        schema_config <- get_golem_config("schema")
        updated_cells <- list()
        affected_columns <- character()
        for (batch_key in names(batch)) {
          edit <- batch[[batch_key]]
          col_editable <- isTRUE(schema_config[[edit$col]]$editable %||% TRUE)
          if (!col_editable) {
            awn::notify(
              sprintf("Column '%s' is not editable. Changes cannot be saved.", edit$col),
              type = "alert"
            )
            next
          }

          r_row <- edit$row + 1

          # Pass user_id to update_cell for audit logging
          user_id_val <- if (!is.null(user_id)) user_id() else NA
          store_reactive()$update_cell(
            row = r_row,
            col = edit$col,
            value = edit$value,
            user_id = user_id_val
          )
          updated_cells[[length(updated_cells) + 1]] <- list(
            row = r_row,
            col = edit$col,
            value = edit$value
          )
          affected_columns <- c(affected_columns, edit$col)
          message("Cell updated: Row ", r_row, ", Col '", edit$col, "', Value: ", edit$value)
        }
        delta_update <- list(
          type = "delta",
          updatedCells = updated_cells,
          modifiedCount = store_reactive()$get_modified_count(),
          affectedColumns = unique(affected_columns)
        )
        .GlobalEnv$last_delta_update <- delta_update
        unique_affected <- unique(affected_columns)
        affected_summary_outputs <- character()
        for (col in unique_affected) {
          if (col %in% names(column_summary_dependencies)) {
            affected_summary_outputs <- c(
              affected_summary_outputs,
              column_summary_dependencies[[col]]
            )
          } else {
            affected_summary_outputs <- c(affected_summary_outputs, "summary_rows")
          }
        }
        affected_summary_outputs <- unique(affected_summary_outputs)
        if ("summary_rows" %in% affected_summary_outputs || "summary_cols" %in% affected_summary_outputs) {
          row_count_trigger(row_count_trigger() + 1)
        }
        if ("summary_age" %in% affected_summary_outputs) {
          age_trigger(age_trigger() + 1)
        }
        if ("summary_bmibl" %in% affected_summary_outputs) {
          bmibl_trigger(bmibl_trigger() + 1)
        }
        modified_trigger(modified_trigger() + 1)
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
        store_trigger(store_trigger() + 1)
      })
      edit_batch(list())
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

        row_count_trigger(row_count_trigger() + 1)
        age_trigger(age_trigger() + 1)
        bmibl_trigger(bmibl_trigger() + 1)
        modified_trigger(modified_trigger() + 1)
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

        row_count_trigger(row_count_trigger() + 1)
        age_trigger(age_trigger() + 1)
        bmibl_trigger(bmibl_trigger() + 1)
        modified_trigger(modified_trigger() + 1)
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
          paste("Revert failed:", clean_msg),
          type = "error")
      })
    })

    # ===== NEW: SUBMISSION WORKFLOW =====

    # Track current submission status
    current_submission_status <- shiny::reactive({
      if (is.null(user_id) || is.null(submission_service)) {
        return(list(id = NA, status = "NO_AUTH"))
      }

      tryCatch({
        submission_service$get_latest_submission(user_id())
      }, error = function(e) {
        list(id = NA, status = "ERROR")
      })
    })

    # Update UI based on submission status (disable edits if PENDING)
    shiny::observe({
      status <- current_submission_status()$status

      if (status == "PENDING") {
        shinyjs::disable("submit")
        shinyjs::disable("save")
        shinyjs::disable("revert")
      } else if (status == "APPROVED") {
        shinyjs::disable("submit")
        shinyjs::disable("save")
        shinyjs::disable("revert")
      } else if (status == "REJECTED") {
        shinyjs::enable("submit")
        shinyjs::enable("save")
      } else {
        shinyjs::enable("submit")
      }
    })

    # Display submission status
    output$submission_status <- renderText({
      status <- current_submission_status()

      if (is.na(status$id)) {
        switch(status$status,
          "NO_AUTH" = "Not authenticated. Cannot submit.",
          "NO_SUBMISSION" = "No submissions yet. Edit and submit.",
          "ERROR" = "Error checking submission status.",
          "Status unavailable"
        )
      } else {
        switch(status$status,
          "DRAFT" = sprintf("Draft saved (ID: %d). Save and submit when ready.", status$id),
          "PENDING" = sprintf("⏳ Awaiting reviewer approval (ID: %d). Editing disabled.", status$id),
          "APPROVED" = sprintf("✅ Approved (ID: %d). Create new submission to edit.", status$id),
          "REJECTED" = sprintf("❌ Rejected (ID: %d). You can re-edit and resubmit.", status$id),
          "Unknown status"
        )
      }
    })

    # Submit button handler
    shiny::observeEvent(input$submit, {
      status <- current_submission_status()

      tryCatch({
        # Enforce permission
        if (!is.null(user_role)) {
          access_control$enforce_action(user_role(), "submit")
        }

        # Show confirmation modal
        shiny::showModal(
          shiny::modalDialog(
            title = "Submit Edits for Review",
            shiny::p("Your edits will be sent to a reviewer for approval."),
            shiny::p(shiny::strong("After submission:"),
              " You cannot edit until the reviewer approves or rejects."),
            shiny::p(sprintf("Modified cells: %d", store_reactive()$get_modified_count())),
            footer = shiny::tagList(
              shiny::modalButton("Cancel"),
              shiny::actionButton(
                session$ns("confirm_submit"),
                "Yes, Submit",
                class = "btn btn-success"
              )
            ),
            easyClose = FALSE
          )
        )
      }, error = function(e) {
        awn::notify(clean_error_message(conditionMessage(e)), type = "alert")
      })
    })

    # Confirm submit handler
    shiny::observeEvent(input$confirm_submit, {
      tryCatch({
        if (is.null(user_id) || is.null(submission_service) || is.null(con)) {
          stop("User context or services not available")
        }

        # Get current data
        current_data <- store_reactive()$data

        # Create submission (DRAFT state)
        submission_id <- submission_service$create_submission(
          user_id = user_id(),
          user_role = user_role(),
          data_snapshot = current_data
        )

        # Transition to PENDING
        submission_service$submit_for_review(
          user_id = user_id(),
          user_role = user_role(),
          submission_id = submission_id
        )

        # Invalidate UI
        store_trigger(store_trigger() + 1)
        shiny::removeModal()

        awn::notify(
          sprintf("Submitted! Submission ID: %d", submission_id),
          type = "success"
        )
      }, error = function(e) {
        shiny::removeModal()
        awn::notify(clean_error_message(conditionMessage(e)), type = "alert")
      })
    })

    output$summary_rows <- renderText({
      row_count_trigger()
      store <- store_reactive()
      summary <- store$summary()
      as.character(summary$rows)
    })

    output$summary_cols <- renderText({
      row_count_trigger()
      store <- store_reactive()
      summary <- store$summary()
      as.character(summary$cols)
    })

    output$summary_age <- renderText({
      age_trigger()
      store <- store_reactive()
      summary <- store$summary()
      if (!is.null(summary$numeric_means) && "AGE" %in% names(summary$numeric_means)) {
        sprintf("%.1f", summary$numeric_means["AGE"])
      } else {
        "N/A"
      }
    })

    output$summary_bmibl <- renderText({
      bmibl_trigger()
      store <- store_reactive()
      summary <- store$summary()
      if (!is.null(summary$numeric_means) && "BMIBL" %in% names(summary$numeric_means)) {
        sprintf("%.1f", summary$numeric_means["BMIBL"])
      } else {
        "N/A"
      }
    })

    output$summary_modified <- renderText({
      modified_trigger()
      store <- store_reactive()
      as.character(store$get_modified_count())
    })
  })
}
