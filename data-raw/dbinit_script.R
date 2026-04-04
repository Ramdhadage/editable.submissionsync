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

# Load packages
library(duckdb)
library(DBI)
library(bcrypt)

# Connect to DuckDB
db_path <- "inst/extdata/adsl.duckdb"
con <- DBI::dbConnect(duckdb::duckdb(), db_path)

# Verify tables exist
tables <- DBI::dbListTables(con)
if (!"users" %in% tables) {
  stop("Table 'users' not found. Run initialize_duckdb_schema() first.")
}

# Clear existing test users (if re-running)
DBI::dbExecute(con, "DELETE FROM users WHERE username IN ('alice', 'bob')")

# Insert test users
# Note: In production, use strong passwords and secure hashing (bcrypt already used)

# User 1: Alice (Editor)
alice_hash <- bcrypt::hashpw("editor123")
DBI::dbExecute(con,
  "INSERT INTO users (username, password_hash, role, email, is_active)
   VALUES (?, ?, ?, ?, 1)",
  params = list("alice", alice_hash, "Editor", "alice@company.com")
)
cat("✓ Created user: alice (Editor)\n")

# User 2: Bob (Reviewer)
bob_hash <- bcrypt::hashpw("reviewer123")
DBI::dbExecute(con,
  "INSERT INTO users (username, password_hash, role, email, is_active)
   VALUES (?, ?, ?, ?, 1)",
  params = list("bob", bob_hash, "Reviewer", "bob@company.com")
)
cat("✓ Created user: bob (Reviewer)\n")

# User 3: Carol (Admin, can do both)
carol_hash <- bcrypt::hashpw("admin123")
DBI::dbExecute(con,
  "INSERT INTO users (username, password_hash, role, email, is_active)
   VALUES (?, ?, ?, ?, 1)",
  params = list("carol", carol_hash, "Admin", "carol@company.com")
)
cat("✓ Created user: carol (Admin)\n")

# Verify
users <- DBI::dbGetQuery(con, "SELECT id, username, role, is_active FROM users ORDER BY id")
cat("\nAll users in database:\n")
print(users)

# Close connection
DBI::dbDisconnect(con)
cat("\n✅ Test users seeded successfully\n")
cat("   Login as alice/editor123 (Editor) or bob/reviewer123 (Reviewer)\n")
