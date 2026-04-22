#' Seed DuckDB with Test Users
#'
#' @description
#' One-time initialization script to seed users table with test accounts.
#' Run this ONCE after schema initialization in development/staging.
#'
#' Change passwords and roles for production.
#'
#' @usage
#' \dontrun{
#'   source("data-raw/dbinit_script.R")
#' }
#'
#' @keywords internal
#' @noRd

# # Load packages
# library(duckdb)
# library(DBI)
# library(bcrypt)
# dbExecute(con, "ALTER TABLE users RENAME COLUMN username TO user;")
#
# # 3. Rename 'password_hash' to 'password'
# dbExecute(con, "ALTER TABLE users RENAME COLUMN password_hash TO password;")
#
# # 4. Verify the changes
# dbListFields(con, "users")
# Connect to DuckDB
db_path <- "inst/extdata/adsl.duckdb"
con <- DBI::dbConnect(duckdb::duckdb(), db_path)

# Verify tables exist
tables <- DBI::dbListTables(con)
if (!"users" %in% tables) {
  stop("Table 'users' not found. Run initialize_duckdb_schema() first.")
}

# Clear existing test users (if re-running)
DBI::dbExecute(con, "DELETE FROM users WHERE user IN ('editor', 'reviewer')")

# Insert test users
# Note: In production, use strong passwords and secure hashing (bcrypt already used)

# User 1: editor (Editor)
editor_hash <- bcrypt::hashpw("123")
DBI::dbExecute(con,
  "INSERT INTO users (user, password, role, email, is_active)
   VALUES (?, ?, ?, ?, 1)",
  params = list("editor", editor_hash, "Editor", "editor@company.com")
)
cat("✓ Created user: editor (Editor)\n")

# User 2: reviewer (Reviewer)
reviewer_hash <- bcrypt::hashpw("123")
DBI::dbExecute(con,
  "INSERT INTO users (user, password, role, email, is_active)
   VALUES (?, ?, ?, ?, 1)",
  params = list("reviewer", reviewer_hash, "Reviewer", "reviewer@company.com")
)
cat("✓ Created user: reviewer (Reviewer)\n")

# User 3: admin (Admin, can do both)
admin_hash <- bcrypt::hashpw("123")
DBI::dbExecute(con,
  "INSERT INTO users (user, password, role, email, is_active)
   VALUES (?, ?, ?, ?, 1)",
  params = list("admin", admin_hash, "Admin", "admin@company.com")
)
cat("✓ Created user: admin (Admin)\n")

# Verify
users <- DBI::dbGetQuery(con, "SELECT id, user, role, is_active FROM users ORDER BY id")
cat("\nAll users in database:\n")
print(users)

# Close connection
DBI::dbDisconnect(con)
cat("\n✅ Test users seeded successfully\n")
cat("   Login as editor/123 (Editor) or reviewer/123 (Reviewer)\n")
