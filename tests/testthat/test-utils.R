test_that("validate_db_path returns valid path when file exists", {
  result <- validate_db_path()
  expect_true(file.exists(result))
  expect_true(endsWith(result, "mtcars.duckdb"))
})

test_that("validate_db_path accepts custom parameters", {
  result <- validate_db_path(
    package = "editable",
    subdir = "extdata",
    filename = "mtcars.duckdb"
  )
  expect_true(file.exists(result))
})

test_that("validate_db_path throws cli_abort when file does not exist", {
  expect_error(
    validate_db_path(filename = "nonexistent.duckdb"),
    class = "rlang_error"
  )
})

test_that("validate_db_path throws cli_abort when package does not exist", {
  expect_error(
    validate_db_path(package = "nonexistent.package"),
    class = "rlang_error"
  )
})

test_that("validate_db_path returns readable canonical database file", {
  db_path <- validate_db_path()

  # Verify file exists and is readable
  expect_true(file.exists(db_path))
  file_size <- file.size(db_path)
  expect_true(file_size > 0)

  # Verify it is the canonical bundled database
  expect_true(endsWith(db_path, "mtcars.duckdb"))
  expect_true(grepl("extdata", db_path))
})

test_that("establish_duckdb_connection can open canonical database in read-write mode", {
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path, read_only = FALSE)

  expect_s4_class(con, "DBIConnection")
  expect_true(DBI::dbIsValid(con))

  # Cleanup
  DBI::dbDisconnect(con, shutdown = TRUE)
})

test_that("establish_duckdb_connection can open canonical database in read-only mode", {
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path, read_only = TRUE)

  expect_s4_class(con, "DBIConnection")
  expect_true(DBI::dbIsValid(con))

  # Cleanup
  DBI::dbDisconnect(con, shutdown = TRUE)
})

test_that("establish_duckdb_connection throws cli_abort for invalid database path", {
  expect_error(
    establish_duckdb_connection("/nonexistent/db.duckdb"),
    class = "rlang_error"
  )
})

test_that("load_mtcars_data loads entire table from canonical database", {
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path)

  result <- load_mtcars_data(con, table = "mtcars")

  expect_s3_class(result, "data.frame")
  expect_gt(nrow(result), 0)
  expect_gt(ncol(result), 0)
  expect_equal(nrow(result), 32)  # mtcars has 32 rows
  DBI::dbDisconnect(con, shutdown = TRUE)
})

test_that("load_mtcars_data preserves column types from canonical database", {
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path)

  result <- load_mtcars_data(con, table = "mtcars")
  result_numeric <- subset(result, select = c("mpg", "disp", "hp", "drat", "wt", "qsec"))
  result_logical <- subset(result, select = "am")
  result_catogorical <- subset(result, select = c("cyl", "vs", "gear", "carb"))
  # mtcars columns should be numeric or integer
  expect_true(all(sapply(result_numeric, is.numeric)))
  expect_true(all(sapply(result_logical, is.logical)))
  expect_true(all(sapply(result_catogorical, is.factor)))

  # Cleanup
  DBI::dbDisconnect(con, shutdown = TRUE)
})

test_that("load_mtcars_data returns empty data.frame on query failure", {
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path)

  # Try to load non-existent table (graceful degradation)
  result <- suppressWarnings(
    load_mtcars_data(con, table = "invalid_table_name")
  )
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  # Cleanup
  DBI::dbDisconnect(con, shutdown = TRUE)
})

test_that("load_mtcars_data warns but does not abort on table not found", {
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path)

  # This should warn, not error
  result <-  expect_warning(load_mtcars_data(con,
                                    table = "invalid_table_name"),
                   "Failed to load table from DuckDB"
    )
  # Cleanup
  DBI::dbDisconnect(con, shutdown = TRUE)
})

test_that("DataStore initializes successfully with all utility functions", {
  store <- DataStore$new()

  expect_s3_class(store, "DataStore")
  expect_s4_class(store$con, "DBIConnection")
  expect_s3_class(store$data, "data.frame")
  expect_s3_class(store$original, "data.frame")
  expect_equal(nrow(store$data), 32)
  expect_equal(nrow(store$original), 32)

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore stores immutable and mutable copies separately", {
  store <- DataStore$new()

  # Modify data
  store$update_cell(1, "mpg", 99.9)

  expect_equal(store$data[1, "mpg"], 99.9)
  expect_failure(expect_equal(store$data[1, "mpg"], store$original[1, "mpg"]))

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore can revert modifications", {
  store <- DataStore$new()

  original_value <- store$original[1, "mpg"]
  store$update_cell(1, "mpg", 99.9)
  expect_equal(store$data[1, "mpg"], 99.9)

  store$revert()
  expect_equal(store$data[1, "mpg"], original_value)

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore properly tracks modified cells", {
  store <- DataStore$new()

  expect_equal(store$get_modified_count(), 0)

  store$update_cell(1, "mpg", 99.9)
  expect_equal(store$get_modified_count(), 1)

  store$update_cell(2, "cyl", 8)
  expect_equal(store$get_modified_count(), 2)

  store$revert()
  expect_equal(store$get_modified_count(), 0)

  # Cleanup
  rm(store)
  gc()
})

# Tests for update_cell utility functions
test_that("validate_data accepts valid data.frame", {
  expect_invisible(validate_data(mtcars))
})

test_that("validate_data throws cli_abort for NULL data", {
  expect_error(
    validate_data(NULL),
    class = "rlang_error"
  )
})

test_that("validate_data throws cli_abort for non-data.frame", {
  expect_error(
    validate_data(list(a = 1, b = 2)),
    class = "rlang_error"
  )
})

test_that("validate_row accepts valid row index", {
  expect_invisible(validate_row(1, mtcars))
  expect_invisible(validate_row(32, mtcars))  # Last row of mtcars
})

test_that("validate_row throws cli_abort for row below range", {
  expect_error(
    validate_row(0, mtcars),
    class = "rlang_error"
  )
})

test_that("validate_row throws cli_abort for row above range", {
  expect_error(
    validate_row(33, mtcars),
    class = "rlang_error"
  )
})

test_that("validate_row throws cli_abort for non-integer row", {
  expect_error(
    validate_row("1", mtcars),
    class = "rlang_error"
  )
})

test_that("validate_column returns column name when given character", {
  result <- validate_column("mpg", mtcars)
  expect_equal(result, "mpg")
})

test_that("validate_column returns column name when given valid numeric index", {
  result <- validate_column(1, mtcars)
  expect_equal(result, "mpg")

  result <- validate_column(11, mtcars)
  expect_equal(result, "carb")
})

test_that("validate_column throws cli_abort for invalid character column", {
  expect_error(
    validate_column("invalid_col", mtcars),
    class = "rlang_error"
  )
})

test_that("validate_column throws cli_abort for numeric index out of bounds", {
  expect_error(
    validate_column(0, mtcars),
    class = "rlang_error"
  )

  expect_error(
    validate_column(12, mtcars),  # mtcars has 11 columns
    class = "rlang_error"
  )
})

test_that("coerce_value coerces numeric correctly", {
  result <- coerce_value(22.5, "mpg", mtcars)
  expect_equal(result, 22.5)
  expect_type(result, "double")
})

test_that("coerce_value coerces integer correctly", {
  test_df <- data.frame(
    int_col = c(1L, 2L, 3L),
    num_col = c(1.5, 2.5, 3.5),
    char_col = c("Ram", "Akbar", "John")
  )
  result <- coerce_value(6, "int_col", test_df)
  expect_equal(result, 6L)
  expect_type(result, "integer")
})

test_that("coerce_value coerces character correctly", {
  test_df <- data.frame(
    int_col = c(1L, 2L, 3L),
    num_col = c(1.5, 2.5, 3.5),
    char_col = c("Ram", "Akbar", "John")
  )
  result <- coerce_value(123, "char_col", test_df)
  expect_equal(result, "123")
  expect_type(result, "character")
})

test_that("coerce_value throws cli_abort for incompatible type", {
  test_df <- data.frame(
    date_col = as.Date(c("2020-01-01", "2020-01-02"))
  )
  expect_error(
    coerce_value(list(a = 1), "date_col", test_df),
    class = "rlang_error"
  )
})

test_that("validate_no_na_loss accepts valid coerced values", {
  expect_invisible(validate_no_na_loss(22.5, 22.5, "mpg"))
  expect_invisible(validate_no_na_loss(NA_real_, NA_real_, "mpg"))
})

test_that("validate_no_na_loss throws cli_abort when value coerces to NA", {
  expect_error(
    validate_no_na_loss(NA_real_, 22.5, "mpg"),
    class = "rlang_error"
  )

  expect_error(
    validate_no_na_loss(NA_character_, "test", "some_col"),
    class = "rlang_error"
  )
})

test_that("validate_no_na_loss allows NA to NA transitions", {
  expect_invisible(validate_no_na_loss(NA_real_, NA_real_, "mpg"))
  expect_invisible(validate_no_na_loss(NA_character_, NA_character_, "col"))
})

test_that("update_cell integrates all validators correctly", {
  store <- DataStore$new()

  # Valid update
  expect_invisible(store$update_cell(1, "mpg", 25.5))
  expect_equal(store$data[1, "mpg"], 25.5)

  # Update with column index
  expect_invisible(store$update_cell(2, 3, 8))
  expect_equal(as.numeric(as.vector(store$data[2, "cyl"])), 8)

  # Cleanup
  rm(store)
  gc()
})

test_that("update_cell throws cli_abort on invalid row", {
  store <- DataStore$new()

  expect_error(
    store$update_cell(0, "mpg", 25.5),
    class = "rlang_error"
  )

  expect_error(
    store$update_cell(100, "mpg", 25.5),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("update_cell throws cli_abort on invalid column", {
  store <- DataStore$new()

  expect_error(
    store$update_cell(1, "invalid_col", 25.5),
    class = "rlang_error"
  )

  expect_error(
    store$update_cell(1, 100, 25.5),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("update_cell throws cli_abort on type coercion failure", {
  store <- DataStore$new()

  expect_error(
    store$update_cell(1, "mpg", "not_a_number"),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("update_cell properly increments modified_cells counter", {
  store <- DataStore$new()

  expect_equal(store$get_modified_count(), 0)

  store$update_cell(1, "mpg", 25.5)
  expect_equal(store$get_modified_count(), 1)

  store$update_cell(2, "cyl", 8)
  expect_equal(store$get_modified_count(), 2)

  store$update_cell(1, "mpg", 26.0)
  expect_equal(store$get_modified_count(), 3)

  # Cleanup
  rm(store)
  gc()
})
test_that("validate_summary_data passes with valid data.frame", {
  expect_invisible(validate_summary_data(mtcars))
})

test_that("validate_summary_data throws cli_abort on NULL data", {
  expect_error(
    validate_summary_data(NULL),
    class = "rlang_error"
  )
})

test_that("validate_summary_data throws cli_abort on non-data.frame", {
  expect_error(
    validate_summary_data(c(1, 2, 3)),
    class = "rlang_error"
  )
})
test_that("detect_numeric_columns finds numeric columns in mtcars", {
  mtcars1 <- mtcars
  mtcars1$am <- factor(mtcars1$am)
  result <- detect_numeric_columns(mtcars1)
  expect_true(is.character(result))
  expect_true("mpg" %in% result)
  expect_true("hp" %in% result)
  expect_true("cyl" %in% result)
  expect_false("am" %in% result)  # am is stored as numeric but often treated as factor
})

test_that("detect_numeric_columns returns all names for all-numeric data", {
  all_numeric <- data.frame(a = 1:5, b = 6:10, c = 11:15)
  result <- detect_numeric_columns(all_numeric)
  expect_equal(sort(result), c("a", "b", "c"))
})

test_that("detect_numeric_columns returns empty vector when no numeric columns", {
  no_numeric <- data.frame(
    x = c("a", "b", "c"),
    y = c("d", "e", "f")
  )
  result <- detect_numeric_columns(no_numeric)
  expect_equal(result, character(0))
})

test_that("detect_numeric_columns handles mixed types correctly", {
  mixed <- data.frame(
    num1 = 1:3,
    char = c("a", "b", "c"),
    num2 = c(1.5, 2.5, 3.5),
    logical = c(TRUE, FALSE, TRUE)
  )
  result <- detect_numeric_columns(mixed)
  expect_equal(sort(result), c("num1", "num2"))
})

test_that("calculate_column_means returns correct means", {
  numeric_cols <- c("mpg", "hp")
  result <- calculate_column_means(mtcars, numeric_cols)
  expect_true(is.numeric(result))
  expect_equal(names(result), numeric_cols)
  expect_equal(as.vector(result["mpg"]), mean(mtcars$mpg, na.rm = TRUE), tolerance = 0.001)
  expect_equal(as.vector(result["hp"]), mean(mtcars$hp, na.rm = TRUE), tolerance = 0.001)
})

test_that("calculate_column_means returns NULL for empty column vector", {
  result <- calculate_column_means(mtcars, character(0))
  expect_null(result)
})

test_that("calculate_column_means handles data with NAs", {
  data_with_na <- mtcars
  data_with_na$mpg[1] <- NA
  data_with_na$hp[2] <- NA

  result <- calculate_column_means(data_with_na, c("mpg", "hp"))

  # Should still work with NA removal
  expect_true(is.numeric(result))
  expect_equal(as.vector(result["mpg"]), mean(data_with_na$mpg, na.rm = TRUE), tolerance = 0.001)
  expect_equal(as.vector(result["hp"]), mean(data_with_na$hp, na.rm = TRUE), tolerance = 0.001)
})

test_that("DataStore$summary returns valid structure with all fields", {
  store <- DataStore$new()

  result <- store$summary()

  expect_true(is.list(result))
  expect_named(result, c("message", "rows", "cols", "numeric_means"))
  expect_true(is.character(result$message))
  expect_true(is.integer(result$rows))
  expect_true(is.integer(result$cols))

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$summary dimensions match actual data", {
  store <- DataStore$new()

  result <- store$summary()

  expect_equal(result$rows, nrow(store$data))
  expect_equal(result$cols, ncol(store$data))

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$summary includes numeric means", {
  store <- DataStore$new()

  result <- store$summary()

  expect_true(is.numeric(result$numeric_means))
  expect_true(length(result$numeric_means) > 0)
  # Verify some expected mtcars numeric columns
  expect_true("mpg" %in% names(result$numeric_means))
  expect_true("hp" %in% names(result$numeric_means))

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$summary throws cli_abort when data is NULL", {
  store <- DataStore$new()
  store$data <- NULL  # Intentionally corrupt

  expect_error(
    store$summary(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$summary message formatting is correct", {
  store <- DataStore$new()

  result <- store$summary()

  expected_message <- sprintf(
    "Rows: %d | Columns: %d",
    nrow(store$data),
    ncol(store$data)
  )
  expect_equal(result$message, expected_message)

  # Cleanup
  rm(store)
  gc()
})

test_that("validate_save_connection passes with valid connection", {
  store <- DataStore$new()

  # Valid connection should pass invisibly
  expect_invisible(validate_save_connection(store$con))

  # Cleanup
  rm(store)
  gc()
})

test_that("validate_save_connection throws cli_abort for NULL connection", {
  expect_error(
    validate_save_connection(NULL),
    class = "rlang_error"
  )
})

test_that("validate_save_connection throws cli_abort for invalid connection", {
  expect_error(
    validate_save_connection(list(fake = "connection")),
    class = "rlang_error"
  )
})

test_that("validate_save_connection throws cli_abort for closed connection", {
  store <- DataStore$new()
  con <- store$con

  # Close the connection
  DBI::dbDisconnect(con, shutdown = TRUE)

  # Should throw error for invalid/closed connection
  expect_error(
    validate_save_connection(con),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("validate_save_data passes with valid data.frame", {
  expect_invisible(validate_save_data(mtcars))
})

test_that("validate_save_data throws cli_abort for NULL data", {
  expect_error(
    validate_save_data(NULL),
    class = "rlang_error"
  )
})

test_that("validate_save_data throws cli_abort for non-data.frame", {
  expect_error(
    validate_save_data(list(a = 1, b = 2)),
    class = "rlang_error"
  )
})

test_that("validate_save_data throws cli_abort for empty data.frame", {
  empty_df <- data.frame()

  expect_error(
    validate_save_data(empty_df),
    class = "rlang_error"
  )
})

test_that("delete_mtcars_table succeeds when table exists", {

  store <- DataStore$new()

  # Table should exist after initialization
  expect_true(DBI::dbExistsTable(store$con, "mtcars"))

  # Delete table
  expect_invisible(delete_mtcars_table(store$con))

  # Verify table is deleted
  expect_false(DBI::dbExistsTable(store$con, "mtcars"))

  # Cleanup
  rm(store)
  gc()
})

test_that("delete_mtcars_table succeeds when table does not exist", {
  # Ensure mtcars table exists first (may be deleted from previous test)
  db_path <- validate_db_path()
  con <- establish_duckdb_connection(db_path)
  if (!DBI::dbExistsTable(con, "mtcars")) {
    write_mtcars_to_db(con, mtcars)
  }
  DBI::dbDisconnect(con, shutdown = TRUE)

  # Now create store with restored table
  store <- DataStore$new()

  # Delete table first
  delete_mtcars_table(store$con)
  expect_false(DBI::dbExistsTable(store$con, "mtcars"))

  # Delete again should still succeed (IF EXISTS clause)
  expect_invisible(delete_mtcars_table(store$con))

  # Restore table for subsequent tests
  write_mtcars_to_db(store$con, mtcars)

  # Cleanup
  rm(store)
  gc()
})

test_that("delete_mtcars_table throws cli_abort for invalid connection", {
  expect_error(
    delete_mtcars_table(NULL),
    class = "rlang_error"
  )
})

test_that("write_mtcars_to_db writes data successfully", {
  store <- DataStore$new()

  # Delete existing table
  delete_mtcars_table(store$con)
  expect_false(DBI::dbExistsTable(store$con, "mtcars"))

  # Write canonical mtcars data (not store$data which may be empty)
  expect_invisible(write_mtcars_to_db(store$con, mtcars))

  # Verify table was created and contains data
  expect_true(DBI::dbExistsTable(store$con, "mtcars"))
  saved_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(nrow(saved_data), nrow(mtcars))
  expect_equal(ncol(saved_data), ncol(mtcars))

  # Cleanup
  rm(store)
  gc()
})

test_that("write_mtcars_to_db overwrites existing data", {
  store <- DataStore$new()

  # Prepare data: start with full mtcars
  test_data <- mtcars
  test_data[1, "mpg"] <- 99.9
  expect_invisible(write_mtcars_to_db(store$con, test_data))

  # Verify first value was written
  saved_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(saved_data[1, "mpg"], 99.9)

  # Modify and save second copy
  test_data[1, "mpg"] <- 88.8
  expect_invisible(write_mtcars_to_db(store$con, test_data))

  # Verify second value overwrote first
  saved_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(saved_data[1, "mpg"], 88.8)

  # Cleanup
  rm(store)
  gc()
})

test_that("write_mtcars_to_db throws cli_abort for invalid connection", {
  expect_error(
    write_mtcars_to_db(NULL, mtcars),
    class = "rlang_error"
  )
})

test_that("DataStore$save() saves data successfully", {
  store <- DataStore$new()

  # Modify data
  store$update_cell(1, "mpg", 25.5)
  expect_equal(store$get_modified_count(), 1)

  # Save changes
  result <- store$save()

  # Should return invisible self
  expect_s3_class(result, "DataStore")

  # Modified count should reset
  expect_equal(store$get_modified_count(), 0)

  # Original should now match data
  expect_equal(store$data, store$original)

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$save() persists data to DuckDB", {
  store <- DataStore$new()

  # Modify and save
  original_mpg <- store$original[1, "mpg"]
  store$update_cell(1, "mpg", 25.5)
  store$save()

  # Verify data was saved to database
  saved_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(saved_data[1, "mpg"], 25.5)

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$save() updates original snapshot", {
  store <- DataStore$new()

  # Ensure full mtcars data (may be empty from previous test)
  if (nrow(store$data) < 32) {
    delete_mtcars_table(store$con)
    write_mtcars_to_db(store$con, mtcars)
    store$data <- load_mtcars_data(store$con)
    store$original <- store$data
  }

  original_baseline <- store$original

  store$update_cell(1, "mpg", 25.5)
  store$update_cell(2, "cyl", 8)

  store$save()

  expect_equal(store$original[1, "mpg"], 25.5)
  expect_equal(as.numeric(as.vector(store$original[2, "cyl"])), 8)

  expect_failure(expect_equal(store$original, original_baseline))

  rm(store)
  gc()
})

test_that("DataStore$save() resets modified_cells counter", {
  store <- DataStore$new()

  # Ensure full mtcars data (may be empty from previous test)
  if (nrow(store$data) < 32) {
    delete_mtcars_table(store$con)
    write_mtcars_to_db(store$con, mtcars)
    store$data <- load_mtcars_data(store$con)
    store$original <- store$data
  }

  # Make multiple modifications
  store$update_cell(1, "mpg", 25.5)
  store$update_cell(2, "cyl", 8)
  store$update_cell(3, "hp", 150)

  expect_equal(store$get_modified_count(), 3)

  # Save
  store$save()

  # Counter should reset
  expect_equal(store$get_modified_count(), 0)

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$save() throws cli_abort when connection is NULL", {
  store <- DataStore$new()
  store$con <- NULL

  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$save() throws cli_abort when data is NULL", {
  store <- DataStore$new()
  store$data <- NULL

  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("DataStore$save() works across multiple cycles", {
  store <- DataStore$new()

  # Ensure full mtcars data (may be empty from previous test)
  if (nrow(store$data) < 32) {
    delete_mtcars_table(store$con)
    write_mtcars_to_db(store$con, mtcars)
    store$data <- load_mtcars_data(store$con)
    store$original <- store$data
  }

  # First cycle
  store$update_cell(1, "mpg", 25.5)
  expect_equal(store$get_modified_count(), 1)

  store$save()
  expect_equal(store$get_modified_count(), 0)
  expect_equal(store$data[1, "mpg"], 25.5)
  expect_equal(store$original[1, "mpg"], 25.5)

  # Second cycle
  store$update_cell(2, "cyl", 8)
  expect_equal(store$get_modified_count(), 1)

  store$save()
  expect_equal(store$get_modified_count(), 0)
  expect_equal(as.numeric(as.vector(store$data[2, "cyl"])), 8)
  expect_equal(as.numeric(as.vector(store$original[2, "cyl"])), 8)

  # Verify database has latest data
  saved_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(saved_data[1, "mpg"], 25.5)
  expect_equal(as.numeric(as.vector(saved_data[2, "cyl"])), 8)

  # Cleanup
  rm(store)
  gc()
})
