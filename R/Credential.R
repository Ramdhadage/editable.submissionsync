#' In-Memory Credential Store
#'
#' @description
#' Defines the in-memory credentials used by shinymanager for authentication.
#'
#' Columns required by shinymanager:
#'   - user     : login username (character)
#'   - password : plain-text password (character) — shinymanager compares directly
#'                in in-memory mode. See NOTE below for production hardening.
#'   - start    : Date the account becomes active (NA = no restriction)
#'   - expire   : Date the account expires        (NA = never expires)
#'   - admin    : Logical — TRUE grants access to the shinymanager /admin panel
#'                and is used inside app_server to gate admin-only UI sections.
#'
#' NOTE — Production hardening (when you switch to SQLite/Postgres):
#'   Replace plain-text passwords with scrypt hashes:
#'     scrypt::hashPassword("your_password")
#'   shinymanager's create_db() does this automatically for database-backed stores.
#'
#' @format A data.frame with one row per user.
#' @noRd
credentials <- data.frame(
  user     = c("admin",      "user1"),
  password = c("Admin@123",  "User@123"),
  start    = as.Date(NA),
  expire   = as.Date(NA),
  admin    = c(TRUE,         FALSE),
  stringsAsFactors = FALSE
)
