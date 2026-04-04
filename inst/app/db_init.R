#' Initialize DuckDB Schema (Idempotent)
#'
#' @description
#' Create all required tables for audit trail, workflow, and user management.
#' Uses IF NOT EXISTS, so safe to call multiple times.
#'
#' @param con DBI connection to adsl.duckdb
#'
#' @keywords internal
#' @noRd
initialize_duckdb_schema <- function(con) {
  tryCatch({
    # ===== Table 1: Users =====
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('Editor', 'Reviewer', 'Admin')),
        email TEXT,
        is_active BOOLEAN DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ")
    cli::cli_alert_info("Table 'users' initialized")

    # ===== Table 2: Sessions (optional, for instrumentation) =====
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id),
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_activity DATETIME DEFAULT CURRENT_TIMESTAMP,
        ip_address TEXT,
        user_agent TEXT
      )
    ")
    cli::cli_alert_info("Table 'sessions' initialized")

    # ===== Table 3: Submissions =====
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS submissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_by INTEGER NOT NULL REFERENCES users(id),
        data_json TEXT NOT NULL,
        status TEXT DEFAULT 'DRAFT'
          CHECK(status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED')),
        submitted_at DATETIME,
        reviewed_by INTEGER REFERENCES users(id),
        reviewed_at DATETIME,
        review_comment TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ")
    cli::cli_alert_info("Table 'submissions' initialized")

    # ===== Table 4: Audit Log (IMMUTABLE, APPEND-ONLY) =====
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL
          CHECK(event_type IN ('LOGIN', 'LOGOUT', 'EDIT', 'SUBMIT',
                              'APPROVE', 'REJECT', 'EXPORT', 'DELETE')),
        user_id INTEGER REFERENCES users(id),
        submission_id INTEGER REFERENCES submissions(id),
        table_name TEXT,
        row_index INTEGER,
        column_name TEXT,
        old_value TEXT,
        new_value TEXT,
        reason TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        ip_address TEXT,
        user_agent TEXT
      )
    ")
    cli::cli_alert_info("Table 'audit_log' (immutable) initialized")

    # ===== Create Indexes for Performance =====
    # Submissions: by status, created_by, created_at
    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_submissions_status
      ON submissions(status)
    ")

    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_submissions_created_by
      ON submissions(created_by)
    ")

    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_submissions_created_at
      ON submissions(created_at DESC)
    ")

    # Audit: by submission, user, timestamp
    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_audit_submission
      ON audit_log(submission_id)
    ")

    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_audit_user
      ON audit_log(user_id)
    ")

    DBI::dbExecute(con, "
      CREATE INDEX IF NOT EXISTS idx_audit_timestamp
      ON audit_log(timestamp DESC)
    ")

    cli::cli_alert_success("DuckDB schema initialized successfully")
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Failed to initialize DuckDB schema",
      "x" = "{conditionMessage(e)}"
    ))
  })
}
