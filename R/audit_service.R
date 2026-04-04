#' Immutable Audit Logging Service
#'
#' @description
#' Append-only audit log tracking all user actions: edits, submissions, approvals, rejections.
#' Audit entries are NEVER updated or deleted (enforced by design convention).
#'
#' @keywords internal
#' @noRd
AuditService <- R6::R6Class(
  "AuditService",
  public = list(
    #' @description Initialize audit service with database connection
    #' @param con DBI connection to adsl.duckdb
    initialize = function(con) {
      private$con <- con
      
      # Ensure audit_log table exists
      tryCatch({
        DBI::dbExecute(private$con, "
          CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER,
            event_type TEXT,
            user_id TEXT,
            submission_id INTEGER,
            table_name TEXT,
            row_index INTEGER,
            column_name TEXT,
            old_value TEXT,
            new_value TEXT,
            reason TEXT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ip_address TEXT,
            user_agent TEXT
          )
        ")
      }, error = function(e) {
        # Table may already exist or there's a schema incompatibility
        # This is not critical as we have error handling in log_event
      })
    },

    #' @description Log a generic event (internal use; use specific log_* methods)
    #' @param event_type Character. Event type (LOGIN, LOGOUT, EDIT, SUBMIT, APPROVE, REJECT, EXPORT).
    #' @param user_id Integer. User ID performing action.
    #' @param submission_id Integer. Submission ID (if applicable).
    #' @param table_name Character. Table affected (if data operation).
    #' @param row_index Integer. Row index affected (if cell edit).
    #' @param column_name Character. Column name affected (if cell edit).
    #' @param old_value Character. Old value (if update).
    #' @param new_value Character. New value (if update).
    #' @param reason Character. Reason (if approval/rejection).
    #' @param ip_address Character. Client IP (optional).
    #' @param user_agent Character. Client user agent (optional).
    #'
    #' @return Invisible TRUE on success.
    log_event = function(event_type, user_id, submission_id = NA,
                        table_name = NA, row_index = NA,
                        column_name = NA, old_value = NA, new_value = NA,
                        reason = NA, ip_address = NA, user_agent = NA) {
      tryCatch({
        # Validate event type
        valid_types <- c("LOGIN", "LOGOUT", "EDIT", "SUBMIT", "APPROVE", "REJECT", "EXPORT", "DELETE")
        if (!event_type %in% valid_types) {
          cli::cli_abort("Invalid event_type: {event_type}")
        }

        # Insert immutable row into audit_log
        DBI::dbExecute(private$con,
          "INSERT INTO audit_log
           (event_type, user_id, submission_id, table_name, row_index,
            column_name, old_value, new_value, reason, ip_address, user_agent)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          params = list(
            event_type, user_id, submission_id, table_name, row_index,
            column_name, old_value, new_value, reason, ip_address, user_agent
          )
        )

        invisible(TRUE)
      }, error = function(e) {
        cli::cli_warn(c(
          "Failed to log audit event (non-blocking)",
          "x" = "{conditionMessage(e)}"
        ))
      })
    },

    #' @description Log a cell edit
    #' @param user_id Integer. User ID.
    #' @param row_idx Integer. Row index (1-based).
    #' @param col_name Character. Column name.
    #' @param old_val Any value. Old value.
    #' @param new_val Any value. New value.
    #'
    #' @return Invisible TRUE.
    log_edit = function(user_id, row_idx, col_name, old_val, new_val) {
      self$log_event(
        event_type = "EDIT",
        user_id = user_id,
        table_name = "adsl",
        row_index = row_idx,
        column_name = col_name,
        old_value = as.character(old_val),
        new_value = as.character(new_val)
      )
    },

    #' @description Log submission for review
    #' @param user_id Integer. User ID submitting.
    #' @param submission_id Integer. Submission ID.
    #'
    #' @return Invisible TRUE.
    log_submit = function(user_id, submission_id) {
      self$log_event(
        event_type = "SUBMIT",
        user_id = user_id,
        submission_id = submission_id
      )
    },

    #' @description Log submission approval
    #' @param user_id Integer. Reviewer user ID.
    #' @param submission_id Integer. Submission ID.
    #' @param reason Character. Approval reason/comments.
    #'
    #' @return Invisible TRUE.
    log_approve = function(user_id, submission_id, reason = "") {
      self$log_event(
        event_type = "APPROVE",
        user_id = user_id,
        submission_id = submission_id,
        reason = reason
      )
    },

    #' @description Log submission rejection
    #' @param user_id Integer. Reviewer user ID.
    #' @param submission_id Integer. Submission ID.
    #' @param reason Character. Rejection reason/comments.
    #'
    #' @return Invisible TRUE.
    log_reject = function(user_id, submission_id, reason = "") {
      self$log_event(
        event_type = "REJECT",
        user_id = user_id,
        submission_id = submission_id,
        reason = reason
      )
    },

    #' @description Query audit trail for compliance reports
    #' @param submission_id Integer. Filter by submission ID (optional).
    #' @param user_id Integer. Filter by user ID (optional).
    #' @param event_type Character. Filter by event type (optional).
    #' @param limit Integer. Max rows to return (default: 1000).
    #'
    #' @return Data frame of audit records, newest first.
    get_audit_trail = function(submission_id = NA, user_id = NA,
                              event_type = NA, limit = 1000) {
      query <- "SELECT * FROM audit_log WHERE 1=1"
      params <- list()

      if (!is.na(submission_id)) {
        query <- paste(query, "AND submission_id = ?")
        params <- c(params, submission_id)
      }
      if (!is.na(user_id)) {
        query <- paste(query, "AND user_id = ?")
        params <- c(params, user_id)
      }
      if (!is.na(event_type)) {
        query <- paste(query, "AND event_type = ?")
        params <- c(params, event_type)
      }

      query <- paste(query, "ORDER BY timestamp DESC LIMIT ?")
      params <- c(params, limit)

      DBI::dbGetQuery(private$con, query, params = params)
    }
  ),

  private = list(
    con = NULL
  )
)

#' @keywords internal
#' @noRd
audit_service <- NULL
