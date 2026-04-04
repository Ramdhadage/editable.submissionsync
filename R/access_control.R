#' Role-Based Access Control Service
#'
#' @description
#' Centralized permission enforcement. All permission checks are validated here.
#' Actions are checked BEFORE handlers execute (not just UI buttons).
#'
#' @keywords internal
#' @noRd
AccessControl <- R6::R6Class(
  "AccessControl",
  public = list(
    #' @description Initialize access control (singleton)
    initialize = function() {
      invisible(self)
    },

    #' @description Check if user can edit cells in table
    #' @param user_role Character. User's role (Editor, Reviewer, Admin)
    #' @return Logical. TRUE if user can edit.
    can_edit = function(user_role) {
      user_role == "Editor"
    },

    #' @description Check if user can submit edits for review
    #' @param user_role Character. User's role.
    #' @return Logical. TRUE if user can submit.
    can_submit = function(user_role) {
      user_role == "Editor"
    },

    #' @description Check if user can review submissions
    #' @param user_role Character. User's role.
    #' @return Logical. TRUE if user can review.
    can_review = function(user_role) {
      user_role %in% c("Reviewer", "Admin")
    },

    #' @description Check if user can export data
    #' @param user_role Character. User's role.
    #' @return Logical. TRUE if user can export.
    can_export = function(user_role) {
      user_role %in% c("Editor", "Reviewer", "Admin")
    },

    #' @description Centralized permission enforcement (throws on denial)
    #' @param user_role Character. User's role.
    #' @param action Character. Action name (edit, submit, review, export).
    #'
    #' @details
    #' If user does not have permission, throws error with context.
    #' Use this within handlers to deny access before processing.
    #'
    #' @return Logical. TRUE on success (invisibly).
    #' @keywords internal
    enforce_action = function(user_role, action) {
      allowed <- switch(action,
        "edit" = self$can_edit(user_role),
        "submit" = self$can_submit(user_role),
        "review" = self$can_review(user_role),
        "export" = self$can_export(user_role),
        FALSE  # Unknown action = denied
      )

      if (!allowed) {
        cli::cli_abort(c(
          "Access denied",
          "i" = "Role: {user_role}",
          "i" = "Action: {action}",
          "x" = "You do not have permission for this action"
        ))
      }

      invisible(TRUE)
    }
  )
)

#' @keywords internal
#' @noRd
access_control <- AccessControl$new()
