
test_that("DataStore initializes correctly from DuckDB", {
  store <- DataStore$new()
  expect_s3_class(store, "DataStore")
  expect_s3_class(store, "R6")
  expect_s4_class(store$con, "duckdb_connection")
  expect_true(is.data.frame(store$data))
  expect_true(is.data.frame(store$original))
  expect_equal(nrow(store$data), 32)
  expect_equal(ncol(store$data), 12)
})

test_that("DataStore maintains immutable original snapshot", {
  store <- DataStore$new()
  original_copy <- store$original

  store$update_cell(1, "mpg", 999)

  expect_equal(store$original, original_copy)
  expect_equal(store$original[1, "mpg"], original_copy[1, "mpg"])
  expect_equal(store$data[1, "mpg"], 999)
})

test_that("update_cell handles numeric columns correctly", {
  # Arrange
  store <- DataStore$new()
  original_value <- store$data[1, "mpg"]

  # Act
  result <- store$update_cell(row = 1, col = "mpg", value = 25.5)

  # Assert
  expect_true(result)
  expect_equal(store$data[1, "mpg"], 25.5)
  expect_type(store$data[1, "mpg"], "double")
})

test_that("update_cell validates row bounds", {
  # Arrange
  store <- DataStore$new()

  # Act & Assert - Row too large
  expect_error(
    store$update_cell(row = 999, col = "mpg", value = 20),
    "Row index out of bounds"
  )

  # Act & Assert - Row too small
  expect_error(
    store$update_cell(row = 0, col = "mpg", value = 20),
    "Row index out of bounds"
  )
})

test_that("update_cell validates column existence", {
  # Arrange
  store <- DataStore$new()

  # Act & Assert
  expect_error(
    store$update_cell(row = 1, col = "nonexistent_column", value = 20),
    "Column not found in dataset"
  )
})

test_that("update_cell validates column index bounds", {
  # Arrange
  store <- DataStore$new()

  # Act & Assert
  expect_error(
    store$update_cell(row = 1, col = 999, value = 20),
    "Column index out of bounds"
  )
})

test_that("update_cell enforces type safety", {
  # Arrange
  store <- DataStore$new()

  # Act & Assert - String to numeric should work (coercion)
  expect_true(store$update_cell(row = 1, col = "mpg", value = "22.5"))
  expect_equal(store$data[1, "mpg"], 22.5)

  # Act & Assert - Invalid string to numeric should fail
  expect_error(
    store$update_cell(row = 1, col = "mpg", value = "not_a_number"),
    "Invalid numeric value 'not_a_number' for column 'mpg'"
  )
})

test_that("revert restores original data and resets counter of modified cells", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Act - Make multiple changes
  store$update_cell(1, "mpg", 999)
  store$update_cell(2, "disp", 12)
  store$update_cell(3, "hp", 500)

  # Assert - Data changed and counter incremented
  expect_equal(store$data[1, "mpg"], 999)
  expect_equal(store$get_modified_count(), 3)

  # Act - Revert
  result <- store$revert()

  # Assert - Data restored to original
  expect_equal(store$data, original_snapshot)
  expect_equal(store$data[1, "mpg"], original_snapshot[1, "mpg"])

  # Assert - Counter reset
  expect_equal(store$get_modified_count(), 0)

  expect_identical(result, store)
})

test_that("revert creates deep copy (not reference)", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Act - Revert
  store$revert()

  # Act - Modify reverted data
  store$data[1, "mpg"] <- 555

  # Assert - Original unchanged (deep copy, not reference)
  expect_equal(store$original[1, "mpg"], original_snapshot[1, "mpg"])
  expect_failure(expect_equal(store$original[1, "mpg"], 555))
})

test_that("revert succeeds with valid original data frame", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 123)

  # Act & Assert - Revert with valid data should succeed
  expect_no_error(store$revert())
  expect_equal(store$get_modified_count(), 0)
})

test_that("revert throws cli_abort when original is NULL", {
  # Arrange
  store <- DataStore$new()
  store$original <- NULL

  # Act & Assert
  expect_error(
    store$revert(),
    class = "rlang_error"
  )
})

test_that("revert throws cli_abort when original is not a data.frame", {
  # Arrange
  store <- DataStore$new()
  store$original <- list(a = 1, b = 2)  # Not a data.frame

  # Act & Assert
  expect_error(
    store$revert(),
    class = "rlang_error"
  )
})

test_that("revert produces cli_inform success message", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 555)

  # Act & Assert - Check for informational message
  expect_message(
    store$revert(),
    "Data reverted to original state"
  )
})

test_that("revert message includes row count", {
  # Arrange
  store <- DataStore$new()
  n_rows <- nrow(store$data)

  # Act & Assert
  expect_message(
    store$revert(),
    sprintf("\\d+ rows")  # Regex to match any number + "rows"
  )
})

test_that("revert maintains immutability after modification", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Act - Modify, then revert
  store$update_cell(1, "mpg", 100)
  store$update_cell(2, "cyl", 8)
  store$revert()

  # Act - Verify original is still unchanged
  expect_equal(store$original, original_snapshot)
})

test_that("revert works multiple times in succession", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Act & Assert - First cycle
  store$update_cell(1, "mpg", 111)
  store$revert()
  expect_equal(store$data, original_snapshot)

  # Act & Assert - Second cycle
  store$update_cell(2, "cyl", 6)
  store$revert()
  expect_equal(store$data, original_snapshot)

  # Act & Assert - Third cycle
  store$update_cell(3, "hp", 999)
  store$revert()
  expect_equal(store$data, original_snapshot)
})

test_that("revert respects all data types (numeric, character, factor, etc.)", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Act - Modify numeric column
  store$update_cell(1, "mpg", 55.5)
  store$update_cell(1, "cyl", 6)

  # Act - Revert
  store$revert()

  # Assert - All types preserved
  expect_equal(typeof(store$data$mpg), typeof(original_snapshot$mpg))
  expect_equal(typeof(store$data$cyl), typeof(original_snapshot$cyl))
  expect_equal(store$data, original_snapshot)
})

test_that("revert integrates with update_cell workflow", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Act - Complex workflow: update multiple cells, revert, update different cells
  store$update_cell(1, "mpg", 100)
  store$update_cell(2, "cyl", 8)
  expect_equal(store$get_modified_count(), 2)

  store$revert()
  expect_equal(store$data, original_snapshot)
  expect_equal(store$get_modified_count(), 0)

  store$update_cell(3, "hp", 200)
  expect_equal(store$get_modified_count(), 1)
  expect_failure(expect_equal(store$data[3, "hp"], original_snapshot[3, "hp"]))
  expect_equal(store$data[1, "mpg"], original_snapshot[1, "mpg"])  # Row 1 unmodified
})

test_that("summary returns correct structure when data loaded", {
  # Arrange
  store <- DataStore$new()

  # Act
  summary <- store$summary()

  # Assert
  expect_type(summary, "list")
  expect_true("message" %in% names(summary))
  expect_true("rows" %in% names(summary))
  expect_true("cols" %in% names(summary))
  expect_true("numeric_means" %in% names(summary))
  expect_equal(summary$rows, 32)
  expect_equal(summary$cols, 12)
  expect_true(grepl("Rows: 32", summary$message))
})

test_that("summary handles numeric means correctly", {
  # Arrange
  store <- DataStore$new()

  # Act
  summary <- store$summary()

  # Assert
  expect_type(summary$numeric_means, "double")
  expect_true("mpg" %in% names(summary$numeric_means))
  expect_true("hp" %in% names(summary$numeric_means))
  expect_true(all(!is.na(summary$numeric_means)))
})

test_that("update_cell handles NULL data gracefully", {
  # Arrange
  store <- DataStore$new()
  store$data <- NULL

  # Act & Assert
  expect_error(
    store$update_cell(1, "mpg", 20),
    "No data loaded"
  )
})

test_that("revert handles NULL original gracefully", {
  # Arrange
  store <- DataStore$new()
  store$original <- NULL

  # Act & Assert
  expect_error(
    store$revert(),
    "Revert operation failed"
  )
})

test_that("summary handles NULL data gracefully", {
  # Arrange
  store <- DataStore$new()
  store$data <- NULL
  # Assert
  expect_error(store$summary(), "Failed to generate summary")
})
test_that("save operation succeeds with valid data and connection", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 99.9)

  # Act & Assert - Save returns invisible self
  result <- store$save()
  expect_identical(result, store)

  # Cleanup
  rm(store)
  gc()
})

test_that("save persists data to DuckDB table", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 88.8)
  store$update_cell(2, "disp", 7)

  # Act
  store$save()

  # Assert - Query database to verify persistence
  db_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(db_data[1, "mpg"], 88.8)
  expect_equal(db_data[2, "disp"], 7)

  # Cleanup
  rm(store)
  gc()
})

test_that("save updates original snapshot to match current data", {
  # Arrange
  store <- DataStore$new()
  original_before_save <- store$original
  store$update_cell(1, "mpg", 77.7)
  expect_failure(expect_equal(store$data[1, "mpg"], original_before_save[1, "mpg"]))

  # Act
  store$save()

  # Assert - Original should now match modified data
  expect_equal(store$original[1, "mpg"], 77.7)
  expect_equal(store$data[1, "mpg"], store$original[1, "mpg"])

  # Cleanup
  rm(store)
  gc()
})

test_that("save resets modified_cells counter to zero", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 66.6)
  store$update_cell(2, "cyl", 4L)
  store$update_cell(3, "hp", 300)
  expect_equal(store$get_modified_count(), 3)

  # Act
  store$save()

  # Assert - Counter should be reset
  expect_equal(store$get_modified_count(), 0)

  # Cleanup
  rm(store)
  gc()
})

test_that("save throws cli_abort when connection is NULL", {
  # Arrange
  store <- DataStore$new()
  store$con <- NULL

  # Act & Assert
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save throws cli_abort when data is NULL", {
  # Arrange
  store <- DataStore$new()
  store$data <- NULL

  # Act & Assert
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save works across multiple modify-save cycles", {
  # Arrange
  store <- DataStore$new()

  # Act & Assert - First cycle
  store$update_cell(1, "mpg", 55.5)
  expect_equal(store$get_modified_count(), 1)
  store$save()
  expect_equal(store$get_modified_count(), 0)
  expect_equal(store$data[1, "mpg"], 55.5)
  expect_equal(store$original[1, "mpg"], 55.5)

  # Act & Assert - Second cycle
  store$update_cell(2, "cyl", 4L)
  expect_equal(store$get_modified_count(), 1)
  store$save()
  expect_equal(store$get_modified_count(), 0)
  expect_equal(as.numeric(as.vector(store$data[2, "cyl"])), 4L)
  expect_equal(as.numeric(as.vector(store$original[2, "cyl"])), 4L)

  # Act & Assert - Third cycle
  store$update_cell(3, "hp", 444)
  expect_equal(store$get_modified_count(), 1)
  store$save()
  expect_equal(store$get_modified_count(), 0)

  # Assert final database state
  db_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(db_data[1, "mpg"], 55.5)
  expect_equal(as.numeric(as.vector(db_data[2, "cyl"])), 4)
  expect_equal(db_data[3, "hp"], 444)

  # Cleanup
  rm(store)
  gc()
})

test_that("save produces cli_inform success message", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 33.3)

  # Act & Assert - Check for informational message
  expect_message(
    store$save(),
    "Data saved to DuckDB"
  )

  # Cleanup
  rm(store)
  gc()
})
test_that("save throws cli_abort when connection is closed before save", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 50.0)

  # Close the connection manually to simulate a connection failure
  DBI::dbDisconnect(store$con, shutdown = TRUE)

  # Act & Assert
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save error message includes database error context", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 50.0)

  # Close connection to force error
  DBI::dbDisconnect(store$con, shutdown = TRUE)

  # Act & Assert
  expect_error(
    store$save(),
    "Save operation failed"
  )

  # Cleanup
  rm(store)
  gc()
})
# ============================================================================
# REVERT VALIDATION - Ensures validation layer works (deep copy error unlikely)
# ============================================================================

test_that("revert validates original data before attempting copy", {
  # Arrange
  store <- DataStore$new()
  original_snapshot <- store$original

  # Intentionally corrupt original to test validation
  store$original <- NULL

  # Act & Assert
  expect_error(
    store$revert(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("revert rejects invalid original data structure", {
  # Arrange
  store <- DataStore$new()

  # Corrupt original with invalid type
  store$original <- "not a data frame"

  # Act & Assert
  expect_error(
    store$revert(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save with empty data frame throws validation error", {
  # Arrange
  store <- DataStore$new()

  # Create empty data frame with same structure but zero rows
  store$data <- store$data[0, ]

  # Act & Assert
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save validates column structure integrity", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 50.0)

  # Corrupt data by removing required column
  store$data$mpg <- NULL

  # Act & Assert - Should fail validation or write
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save maintains data integrity across multiple operations", {
  # Arrange
  store <- DataStore$new()

  # Act - Complex sequence
  store$update_cell(1, "mpg", 11.1)
  store$update_cell(5, "hp", 555)
  store$update_cell(10, "cyl", 4L)
  store$save()

  # Verify database persistence
  db_data <- DBI::dbReadTable(store$con, "mtcars")

  # Assert
  expect_equal(db_data[1, "mpg"], 11.1)
  expect_equal(db_data[5, "hp"], 555)
  expect_equal(as.numeric(as.vector(db_data[10, "cyl"])), 4L)

  # Modify again and save
  store$update_cell(1, "mpg", 22.2)
  store$save()

  db_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(db_data[1, "mpg"], 22.2)

  # Cleanup
  rm(store)
  gc()
})

test_that("save prevents data loss on revert after save", {
  # Arrange
  store <- DataStore$new()
  original_mpg_1 <- store$data[1, "mpg"]

  # Act
  store$update_cell(1, "mpg", 99.9)
  store$save()

  # Modify again
  store$update_cell(1, "mpg", 77.7)

  # Revert to last save (original should be 99.9, not initial value)
  store$revert()

  # Assert
  expect_equal(store$data[1, "mpg"], 99.9)
  expect_failure(expect_equal(store$data[1, "mpg"], original_mpg_1))

  # Cleanup
  rm(store)
  gc()
})

test_that("update_cell fails when connection is closed (indirect test)", {
  # Arrange
  store <- DataStore$new()

  # Disconnect the connection
  DBI::dbDisconnect(store$con, shutdown = TRUE)

  # Act - Update still works (doesn't touch DB), but save will fail
  expect_true(store$update_cell(1, "mpg", 50.0))

  # Verify save fails with closed connection
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save fails gracefully when original snapshot is corrupted", {
  # Arrange
  store <- DataStore$new()
  store$update_cell(1, "mpg", 50.0)

  # Corrupt original to cause state inconsistency
  store$original <- NULL

  # Act & Assert
  expect_error(
    store$save(),
    class = "rlang_error"
  )

  # Cleanup
  rm(store)
  gc()
})

test_that("save rejects data with fewer rows", {
  store <- DataStore$new()
  original_rows <- nrow(store$data)

  # Delete rows
  store$data <- store$data[-1, ]

  expect_error(
    store$save(),
    class = "rlang_error"
  )

  rm(store)
  gc()
})

test_that("save rejects data with more rows", {
  store <- DataStore$new()

  # Add duplicate row
  store$data <- rbind(store$data, store$data[1, ])

  expect_error(
    store$save(),
    class = "rlang_error"
  )

  rm(store)
  gc()
})


test_that("modified_cells counter reflects actual edits", {
  # Arrange
  store <- DataStore$new()

  # Act & Assert
  expect_equal(store$get_modified_count(), 0)

  store$update_cell(1, "mpg", 50.0)
  expect_equal(store$get_modified_count(), 1)

  store$update_cell(2, "cyl", 6L)
  expect_equal(store$get_modified_count(), 2)

  store$update_cell(3, "hp", 300)
  expect_equal(store$get_modified_count(), 3)

  # Save resets counter
  store$save()
  expect_equal(store$get_modified_count(), 0)

  # Revert also resets counter
  store$update_cell(1, "mpg", 60.0)
  expect_equal(store$get_modified_count(), 1)

  store$revert()
  expect_equal(store$get_modified_count(), 0)

  # Cleanup
  rm(store)
  gc()
})
