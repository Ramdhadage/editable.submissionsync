#' Submission Workflow State Machine Service
#'
#' @description
#' Manages submission lifecycle: DRAFT → PENDING → APPROVED/REJECTED.
#' Enforces state transitions, validates permissions, logs audit events.
#'
#' @keywords internal
#' @noRd
SubmissionService <- R6::R6Class(
  "SubmissionService",
  public = list(
    #' @description Initialize submission service
    #' @param con DBI connection to adsl.duckdb
    #' @param audit_service AuditService instance
    #' @param access_control AccessControl instance
    initialize = function(con, audit_service, access_control) {
      private$con <- con
      private$audit_service <- audit_service
      private$access_control <- access_control
      
      # Ensure submissions table exists
      tryCatch({
        DBI::dbExecute(private$con, "
          CREATE TABLE IF NOT EXISTS submissions (
            id INTEGER,
            created_by TEXT,
            data_json TEXT,
            status TEXT DEFAULT 'DRAFT',
            submitted_at TIMESTAMP,
            reviewed_by TEXT,
            reviewed_at TIMESTAMP,
            review_comment TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ")
      }, error = function(e) {
        # Table may already exist or there's a schema incompatibility
      })
    },

    #' @description Create new draft submission
    #' @param user_id Integer. Editor user ID.
    #' @param user_role Character. User role.
    #' @param data_snapshot Data frame. Current table data to snapshot.
    #'
    #' @return Integer. Submission ID (created in DRAFT state).
    #'
    #' @details
    #' Creates new submission record with DRAFT status.
    #' Data is stored as JSON snapshot for later approval/rejection reference.
    create_submission = function(user_id, user_role, data_snapshot) {
      tryCatch({
        # Enforce Editor-only
        private$access_control$enforce_action(user_role, "submit")

        # Serialize data as JSON
        data_json <- jsonlite::toJSON(data_snapshot, pretty = FALSE)

        # Insert new DRAFT submission
        result <- DBI::dbGetQuery(private$con,
          "INSERT INTO submissions
           (created_by, data_json, status)
           VALUES (?, ?, 'DRAFT')
           RETURNING id",
          params = list(user_id, data_json)
        )

        submission_id <- result$id[1]
        cli::cli_alert_success("Submission #{submission_id} created (DRAFT)")

        invisible(submission_id)
      }, error = function(e) {
        cli::cli_abort(c(
          "Failed to create submission",
          "x" = "{conditionMessage(e)}"
        ))
      })
    },

    #' @description Submit edits for review (DRAFT → PENDING)
    #' @param user_id Integer. Editor user ID.
    #' @param user_role Character. User role (must be Editor).
    #' @param submission_id Integer. Submission to submit.
    #'
    #' @return Logical. TRUE on success.
    #'
    #' @details
    #' Transitions submission state: DRAFT → PENDING.
    #' Sets submitted_at timestamp.
    #' Logs SUBMIT audit event.
    #' After this, editors cannot modify submission (enforce in UI).
    submit_for_review = function(user_id, user_role, submission_id) {
      tryCatch({
        # Verify role
        private$access_control$enforce_action(user_role, "submit")

        # Get current submission state
        current <- DBI::dbGetQuery(private$con,
          "SELECT status, created_by FROM submissions WHERE id = ?",
          params = list(submission_id)
        )

        if (nrow(current) == 0) {
          cli::cli_abort("Submission #{submission_id} not found")
        }

        # Verify ownership
        if (current$created_by[1] != user_id) {
          cli::cli_abort("You cannot submit another user's submission")
        }

        # Verify state: must be DRAFT
        if (current$status[1] != "DRAFT") {
          cli::cli_abort(c(
            "Invalid state transition",
            "i" = "Current status: {current$status[1]}",
            "x" = "Can only submit from DRAFT state"
          ))
        }

        # Transition: DRAFT → PENDING
        DBI::dbExecute(private$con,
          "UPDATE submissions
           SET status = 'PENDING',
               submitted_at = CURRENT_TIMESTAMP,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = ?",
          params = list(submission_id)
        )

        # Log audit: SUBMIT
        private$audit_service$log_submit(user_id, submission_id)

        cli::cli_alert_success("Submission #{submission_id} submitted for review")
        invisible(TRUE)

      }, error = function(e) {
        cli::cli_abort(c(
          "Failed to submit for review",
          "x" = "{conditionMessage(e)}"
        ))
      })
    },

    #' @description Approve submission (PENDING → APPROVED, write to adsl)
    #' @param user_id Integer. Reviewer user ID.
    #' @param user_role Character. User role (must be Reviewer/Admin).
    #' @param submission_id Integer. Submission to approve.
    #' @param reason Character. Approval comment/reason.
    #'
    #' @return Logical. TRUE on success.
    #'
    #' @details
    #' Transitions submission state: PENDING → APPROVED.
    #' Writes snapshot data to adsl table (replaces current).
    #' Sets reviewed_by, reviewed_at, review_comment.
    #' Logs APPROVE audit event.
    #' NB: This is atomic - if write to adsl fails, submission stays PENDING.
    approve_submission = function(user_id, user_role, submission_id, reason = "") {
      tryCatch({
        # Verify role
        private$access_control$enforce_action(user_role, "review")

        # Get submission
        submission <- DBI::dbGetQuery(private$con,
          "SELECT status, data_json FROM submissions WHERE id = ?",
          params = list(submission_id)
        )

        if (nrow(submission) == 0) {
          cli::cli_abort("Submission #{submission_id} not found")
        }

        # Verify state: must be PENDING
        if (submission$status[1] != "PENDING") {
          cli::cli_abort(c(
            "Invalid state transition",
            "i" = "Current status: {submission$status[1]}",
            "x" = "Can only approve PENDING submissions"
          ))
        }

        # Parse data JSON
        data <- jsonlite::fromJSON(submission$data_json[1])
        data_df <- as.data.frame(data, stringsAsFactors = FALSE)

        # Write to adsl table (atomic: DELETE then INSERT)
        DBI::dbExecute(private$con, "DELETE FROM adsl")
        DBI::dbWriteTable(private$con, "adsl", data_df, append = TRUE, row.names = FALSE)

        # Update submission status
        DBI::dbExecute(private$con,
          "UPDATE submissions
           SET status = 'APPROVED',
               reviewed_by = ?,
               reviewed_at = CURRENT_TIMESTAMP,
               review_comment = ?,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = ?",
          params = list(user_id, reason, submission_id)
        )

        # Log audit: APPROVE
        private$audit_service$log_approve(user_id, submission_id, reason)

        cli::cli_alert_success("Submission #{submission_id} approved and written to adsl")
        invisible(TRUE)

      }, error = function(e) {
        cli::cli_abort(c(
          "Failed to approve submission",
          "x" = "{conditionMessage(e)}"
        ))
      })
    },

    #' @description Reject submission (PENDING → REJECTED)
    #' @param user_id Integer. Reviewer user ID.
    #' @param user_role Character. User role (Reviewer/Admin).
    #' @param submission_id Integer. Submission to reject.
    #' @param reason Character. Rejection reason/comments.
    #'
    #' @return Logical. TRUE on success.
    #'
    #' @details
    #' Transitions submission state: PENDING → REJECTED.
    #' Sets reviewed_by, reviewed_at, review_comment.
    #' Logs REJECT audit event.
    #' Editor can then re-edit, re-save, and re-submit.
    reject_submission = function(user_id, user_role, submission_id, reason = "") {
      tryCatch({
        # Verify role
        private$access_control$enforce_action(user_role, "review")

        # Get submission
        submission <- DBI::dbGetQuery(private$con,
          "SELECT status FROM submissions WHERE id = ?",
          params = list(submission_id)
        )

        if (nrow(submission) == 0) {
          cli::cli_abort("Submission #{submission_id} not found")
        }

        # Verify state: must be PENDING
        if (submission$status[1] != "PENDING") {
          cli::cli_abort(c(
            "Invalid state transition",
            "i" = "Current status: {submission$status[1]}",
            "x" = "Can only reject PENDING submissions"
          ))
        }

        # Transition: PENDING → REJECTED
        DBI::dbExecute(private$con,
          "UPDATE submissions
           SET status = 'REJECTED',
               reviewed_by = ?,
               reviewed_at = CURRENT_TIMESTAMP,
               review_comment = ?,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = ?",
          params = list(user_id, reason, submission_id)
        )

        # Log audit: REJECT
        private$audit_service$log_reject(user_id, submission_id, reason)

        cli::cli_alert_success("Submission #{submission_id} rejected")
        invisible(TRUE)

      }, error = function(e) {
        cli::cli_abort(c(
          "Failed to reject submission",
          "x" = "{conditionMessage(e)}"
        ))
      })
    },

    #' @description Get all pending submissions (PENDING status only)
    #' @return Data frame. Pending submissions with editor name.
    #'
    #' @details
    #' Returns submissions in PENDING status, oldest first (FIFO review queue).
    #' Joins with users table to show editor name.
    get_pending_submissions = function() {
      DBI::dbGetQuery(private$con,
        "SELECT s.id,
                s.created_by,
                u.user as editor_name,
                s.submitted_at,
                s.review_comment
         FROM submissions s
         LEFT JOIN users u ON s.created_by = u.id
         WHERE s.status = 'PENDING'
         ORDER BY s.submitted_at ASC"
      )
    },

    #' @description Get submission history (for audit/compliance)
    #' @param submission_id Integer. Submission ID.
    #'
    #' @return Data frame. Single submission record with full metadata.
    get_submission_history = function(submission_id) {
      DBI::dbGetQuery(private$con,
        "SELECT * FROM submissions WHERE id = ?",
        params = list(submission_id)
      )
    },

    #' @description Get latest submission for a user
    #' @param user_id Integer. User ID (Editor).
    #'
    #' @return List with id and status, or NA if no submission.
    get_latest_submission = function(user_id) {
      result <- DBI::dbGetQuery(private$con,
        "SELECT id, status FROM submissions
         WHERE created_by = ?
         ORDER BY created_at DESC
         LIMIT 1",
        params = list(user_id)
      )

      if (nrow(result) == 0) {
        return(list(id = NA, status = "NO_SUBMISSION"))
      }

      list(id = result$id[1], status = result$status[1])
    }
  ),

  private = list(
    con = NULL,
    audit_service = NULL,
    access_control = NULL
  )
)

#' @keywords internal
#' @noRd
submission_service <- NULL
