#' User Authentication & Session Management Service
#'
#' @description
#' User management: lookup by ID/user, check active status.
#' Session tracking optional (can use shinymanager's built-in).
#'
#' @keywords internal
#' @noRd
UserAuth <- R6::R6Class(
  "UserAuth",
  public = list(
    #' @description Initialize auth service with database connection
    #' @param con DBI connection to adsl.duckdb
    initialize = function(con) {
      private$con <- con
      
      # Ensure sessions table exists
      tryCatch({
        DBI::dbExecute(private$con, "
          CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ip_address TEXT,
            user_agent TEXT
          )
        ")
      }, error = function(e) {
        # Table may already exist
      })
    },

    #' @description Get user info by ID
    #' @param user_id Integer. User ID.
    #' @return Data frame (one row) or NULL if not found.
    get_user = function(user_id) {
      result <- DBI::dbGetQuery(private$con,
        "SELECT id, user, role, email, is_active FROM users WHERE id = ?",
        params = list(user_id)
      )

      if (nrow(result) == 0) {
        return(NULL)
      }

      result[1, , drop = FALSE]
    },

    #' @description Get user info by user
    #' @param user Character. Username.
    #' @return Data frame (one row) or NULL if not found.
    get_user_by_username = function(user) {
      result <- DBI::dbGetQuery(private$con,
        "SELECT id, user, role, email, is_active FROM users WHERE user = ?",
        params = list(user)
      )

      if (nrow(result) == 0) {
        return(NULL)
      }

      result[1, , drop = FALSE]
    },

    #' @description Check if user is active
    #' @param user_id Integer. User ID.
    #' @return Logical. TRUE if active, FALSE otherwise.
    is_user_active = function(user_id) {
      result <- DBI::dbGetQuery(private$con,
        "SELECT is_active FROM users WHERE id = ?",
        params = list(user_id)
      )

      if (nrow(result) == 0) {
        return(FALSE)
      }

      result$is_active[1] == TRUE
    },

    #' @description List all active users (admin use)
    #' @return Data frame. All active users.
    list_active_users = function() {
      DBI::dbGetQuery(private$con,
        "SELECT id, user, role, email FROM users WHERE is_active = TRUE ORDER BY user"
      )
    }
  ),

  private = list(
    con = NULL
  )
)

#' @keywords internal
#' @noRd
user_auth <- NULL
