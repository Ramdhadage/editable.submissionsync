#' mod_review: Reviewer Dashboard Module
#'
#' @description
#' UI and server logic for reviewers to view pending submissions,
#' approve/reject, and see audit trail.
#'
#' @param id Module namespace ID
#'
#' @keywords internal
#' @noRd

#' Review Module UI
#' @keywords internal
#' @noRd
mod_review_ui <- function(id) {
  ns <- NS(id)

  div(
    class = "container-fluid",
    div(
      class = "row",
      div(
        class = "col-md-3",
        h4("Pending Submissions"),
        tableOutput(ns("pending_table")),
        hr(),
        h4("Actions"),
        numericInput(ns("selected_id"), "Submission ID", value = 0, min = 0),
        textAreaInput(ns("review_comment"), "Comments", rows = 4, placeholder = "Approval or rejection reason..."),
        div(
          class = "d-grid gap-2",
          actionButton(ns("approve_btn"), "Approve", class = "btn-success", width = "100%"),
          actionButton(ns("reject_btn"), "Reject", class = "btn-danger", width = "100%")
        )
      ),
      div(
        class = "col-md-9",
        tabsetPanel(
          type = "tabs",
          tabPanel(
            "Data Preview",
            h4("Submission Data"),
            tableOutput(ns("submission_data"))
          ),
          tabPanel(
            "Audit Trail",
            h4("Event History"),
            tableOutput(ns("audit_trail"))
          ),
          tabPanel(
            "Submission Info",
            h4("Details"),
            textOutput(ns("submission_info"))
          )
        )
      )
    )
  )
}

#' Review Module Server
#' @keywords internal
#' @noRd
mod_review_server <- function(id, con, user_id, user_role, submission_service) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    # Pre-flight: Verify user is Reviewer
    observeEvent(user_role(), {
      tryCatch({
        access_control$enforce_action(user_role(), "review")
      }, error = function(e) {
        cli::cli_abort("User does not have reviewer permission")
      })
    }, once = TRUE)

    # ===== 1. LIST PENDING SUBMISSIONS =====
    pending_submissions <- reactive({
      # Auto-refresh every 10 seconds
      invalidateLater(10000)

      tryCatch({
        submission_service$get_pending_submissions()
      }, error = function(e) {
        data.frame()
      })
    })

    output$pending_table <- renderTable({
      if (nrow(pending_submissions()) == 0) {
        data.frame(Message = "No pending submissions")
      } else {
        pending_submissions() |>
          dplyr::select(id, editor_name, submitted_at)
      }
    }, striped = TRUE, hover = TRUE)

    # ===== 2. LOAD SELECTED SUBMISSION DATA =====
    selected_submission_data <- reactive({
      req(input$selected_id > 0)

      submission_id <- as.integer(input$selected_id)

      tryCatch({
        result <- DBI::dbGetQuery(con(),
          "SELECT data_json FROM submissions WHERE id = ?",
          params = list(submission_id)
        )

        if (nrow(result) == 0) {
          return(NULL)
        }

        jsonlite::fromJSON(result$data_json[1])
      }, error = function(e) {
        cli::cli_abort(sprintf("Failed to load submission %d: {e}", submission_id))
      })
    })

    output$submission_data <- renderTable({
      data <- selected_submission_data()

      if (is.null(data)) {
        return(data.frame(Message = "Select a submission ID to view data"))
      }

      as.data.frame(data, stringsAsFactors = FALSE)
    })

    # ===== 3. SHOW SUBMISSION METADATA =====
    output$submission_info <- renderText({
      req(input$selected_id > 0)

      submission_id <- as.integer(input$selected_id)

      tryCatch({
        result <- DBI::dbGetQuery(con(),
          "SELECT s.id, s.created_by, u.user, s.status, s.submitted_at,
                  s.review_comment
           FROM submissions s
           LEFT JOIN users u ON s.created_by = u.id
           WHERE s.id = ?",
          params = list(submission_id)
        )

        if (nrow(result) == 0) {
          return("Submission not found")
        }

        r <- result[1, ]
        sprintf(
          "ID: %d | Editor: %s | Status: %s | Submitted: %s | Comments: %s",
          r$id, r$user, r$status, r$submitted_at,
          if (is.na(r$review_comment)) "(none)" else r$review_comment
        )
      }, error = function(e) {
        sprintf("Error loading submission info: {conditionMessage(e)}")
      })
    })

    # ===== 4. SHOW AUDIT TRAIL FOR SUBMISSION =====
    output$audit_trail <- renderTable({
      req(input$selected_id > 0)

      submission_id <- as.integer(input$selected_id)

      tryCatch({
        audit_service$get_audit_trail(submission_id = submission_id)
      }, error = function(e) {
        data.frame(Message = "Failed to load audit trail")
      })
    })

    # ===== 5. APPROVE BUTTON =====
    observeEvent(input$approve_btn, {
      req(input$selected_id > 0)

      submission_id <- as.integer(input$selected_id)

      tryCatch({
        # Call service
        submission_service$approve_submission(
          user_id = user_id(),
          user_role = user_role(),
          submission_id = submission_id,
          reason = input$review_comment
        )

        # Clear UI
        shinyjs::reset("review_comment")
        shinyjs::reset("selected_id")

        # Notify user
        awn::awn("success", sprintf("Submission %d approved and written to adsl", submission_id))
      }, error = function(e) {
        awn::awn("error", clean_error_message(conditionMessage(e)))
      })
    })

    # ===== 6. REJECT BUTTON =====
    observeEvent(input$reject_btn, {
      req(input$selected_id > 0)

      submission_id <- as.integer(input$selected_id)

      tryCatch({
        # Call service
        submission_service$reject_submission(
          user_id = user_id(),
          user_role = user_role(),
          submission_id = submission_id,
          reason = input$review_comment
        )

        # Clear UI
        shinyjs::reset("review_comment")
        shinyjs::reset("selected_id")

        # Notify user
        awn::awn("info", sprintf("Submission %d rejected", submission_id))
      }, error = function(e) {
        awn::awn("error", clean_error_message(conditionMessage(e)))
      })
    })
  })
}
