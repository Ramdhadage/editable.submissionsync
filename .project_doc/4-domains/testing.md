# Testing Domain

## Overview

Testing in editable emphasizes **deterministic, comprehensive unit test coverage** with real integrations (not mocks). Key principles:
- All public R6 methods tested
- Edge cases and error conditions covered
- Real DuckDB database used (not mocked)
- Tests isolated and repeatable
- 60+ tests covering happy paths and failure modes

## Test Framework

**Unit Testing Framework**: testthat (CRAN standard)
```r
# tests/testthat.R
library(testthat)
library(editable)

test_check("editable")
```

**Test Configuration**:
```r
# DESCRIPTION
Suggests: 
    shinytest2,
    testthat (>= 3.0.0)
```

## DataStore Tests (tests/testthat/test-DataStore.R)

### Initialization Tests

```r
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
```

**Test Pattern:**
- Fresh DataStore per test (no shared state)
- Verify class hierarchy (S3 + R6)
- Verify connection type
- Verify data structure (data frame, dimensions)

### Immutability Tests

```r
test_that("DataStore maintains immutable original snapshot", {
  store <- DataStore$new()
  original_copy <- store$original
  
  store$update_cell(1, "mpg", 999)
  
  expect_equal(store$original, original_copy)
  expect_equal(store$original[1, "mpg"], original_copy[1, "mpg"])
  expect_equal(store$data[1, "mpg"], 999)
})
```

**Validates:**
- `self$original` unchanged after user edit
- `self$data` reflects the change
- Immutability invariant maintained

### Cell Update Tests

```r
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
```

**Pattern:**
- Arrange: Setup initial state
- Act: Call method under test
- Assert: Verify outcomes
- Returns invisible TRUE on success

### Validation Tests

```r
test_that("update_cell validates row bounds", {
  store <- DataStore$new()
  
  # Row too large
  expect_error(
    store$update_cell(row = 999, col = "mpg", value = 20),
    "Row index out of bounds"
  )
  
  # Row too small
  expect_error(
    store$update_cell(row = 0, col = "mpg", value = 20),
    "Row index out of bounds"
  )
})

test_that("update_cell validates column existence", {
  store <- DataStore$new()
  
  expect_error(
    store$update_cell(row = 1, col = "nonexistent_column", value = 20),
    "Column not found in dataset"
  )
})

test_that("update_cell enforces type safety", {
  store <- DataStore$new()
  
  # String to numeric coercion works
  expect_true(store$update_cell(row = 1, col = "mpg", value = "22.5"))
  expect_equal(store$data[1, "mpg"], 22.5)
  
  # Invalid string to numeric fails
  expect_error(
    store$update_cell(row = 1, col = "mpg", value = "not_a_number"),
    "Invalid numeric value 'not_a_number' for column 'mpg'"
  )
})
```

**Coverage:**
- Bounds checking (out of range)
- Column existence
- Type coercion (valid and invalid)

### Revert Tests

```r
test_that("revert restores original data and resets counter", {
  store <- DataStore$new()
  original_snapshot <- store$original
  
  # Make multiple changes
  store$update_cell(1, "mpg", 999)
  store$update_cell(2, "disp", 12)
  store$update_cell(3, "hp", 500)
  
  # Verify state changed
  expect_equal(store$data[1, "mpg"], 999)
  expect_equal(store$get_modified_count(), 3)
  
  # Revert
  result <- store$revert()
  
  # Verify restoration
  expect_equal(store$data, original_snapshot)
  expect_equal(store$get_modified_count(), 0)
  expect_identical(result, store)  # Returns self for chaining
})

test_that("revert creates deep copy (not reference)", {
  store <- DataStore$new()
  original_snapshot <- store$original
  
  store$revert()
  store$data[1, "mpg"] <- 555  # Modify reverted data
  
  # Original should be unchanged
  expect_equal(store$original[1, "mpg"], original_snapshot[1, "mpg"])
  expect_failure(expect_equal(store$original[1, "mpg"], 555))
})

test_that("revert works multiple times in succession", {
  store <- DataStore$new()
  original_snapshot <- store$original
  
  # First cycle
  store$update_cell(1, "mpg", 111)
  store$revert()
  expect_equal(store$data, original_snapshot)
  
  # Second cycle
  store$update_cell(2, "cyl", 6)
  store$revert()
  expect_equal(store$data, original_snapshot)
  
  # Third cycle
  store$update_cell(3, "hp", 999)
  store$revert()
  expect_equal(store$data, original_snapshot)
})
```

**Edge Cases Tested:**
- Deep copy semantics
- Multiple cycles
- Data type preservation
- Counter reset

### Save Tests

```r
test_that("save operation succeeds with valid data and connection", {
  store <- DataStore$new()
  store$update_cell(1, "mpg", 99.9)
  
  result <- store$save()
  expect_identical(result, store)  # Returns invisible self
  
  rm(store)
  gc()
})

test_that("save persists data to DuckDB table", {
  store <- DataStore$new()
  store$update_cell(1, "mpg", 88.8)
  store$update_cell(2, "disp", 7)
  
  store$save()
  
  # Query DB to verify persistence
  db_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(db_data[1, "mpg"], 88.8)
  expect_equal(db_data[2, "disp"], 7)
  
  rm(store)
  gc()
})

test_that("save updates original snapshot to match current data", {
  store <- DataStore$new()
  original_before_save <- store$original
  store$update_cell(1, "mpg", 77.7)
  expect_failure(expect_equal(store$data[1, "mpg"], original_before_save[1, "mpg"]))
  
  store$save()
  
  # Original should now match modified data
  expect_equal(store$original[1, "mpg"], 77.7)
  expect_equal(store$data[1, "mpg"], store$original[1, "mpg"])
  
  rm(store)
  gc()
})

test_that("save resets modified_cells counter to zero", {
  store <- DataStore$new()
  store$update_cell(1, "mpg", 66.6)
  store$update_cell(2, "cyl", 4L)
  store$update_cell(3, "hp", 300)
  expect_equal(store$get_modified_count(), 3)
  
  store$save()
  
  expect_equal(store$get_modified_count(), 0)
  
  rm(store)
  gc()
})

test_that("save works across multiple modify-save cycles", {
  store <- DataStore$new()
  
  # First cycle
  store$update_cell(1, "mpg", 55.5)
  expect_equal(store$get_modified_count(), 1)
  store$save()
  expect_equal(store$get_modified_count(), 0)
  
  # Second cycle
  store$update_cell(2, "cyl", 4L)
  expect_equal(store$get_modified_count(), 1)
  store$save()
  expect_equal(store$get_modified_count(), 0)
  
  # Verify DB state
  db_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(db_data[1, "mpg"], 55.5)
  expect_equal(as.numeric(as.vector(db_data[2, "cyl"])), 4)
  
  rm(store)
  gc()
})
```

**DB Integration:**
- Actually writes to/reads from DuckDB
- Not mocked
- Cleanup via `rm(store); gc()`

### Error Condition Tests

```r
test_that("save throws cli_abort when connection is NULL", {
  store <- DataStore$new()
  store$con <- NULL
  
  expect_error(
    store$save(),
    class = "rlang_error"
  )
  
  rm(store)
  gc()
})

test_that("save throws cli_abort when data is NULL", {
  store <- DataStore$new()
  store$data <- NULL
  
  expect_error(
    store$save(),
    class = "rlang_error"
  )
  
  rm(store)
  gc()
})

test_that("save rejects data with fewer rows", {
  store <- DataStore$new()
  original_rows <- nrow(store$data)
  
  store$data <- store$data[-1, ]  # Delete first row
  
  expect_error(
    store$save(),
    class = "rlang_error"
  )
  
  rm(store)
  gc()
})

test_that("update_cell fails when connection is closed", {
  store <- DataStore$new()
  DBI::dbDisconnect(store$con, shutdown = TRUE)
  
  # Update still works in-memory
  expect_true(store$update_cell(1, "mpg", 50.0))
  
  # But save fails
  expect_error(
    store$save(),
    class = "rlang_error"
  )
  
  rm(store)
  gc()
})
```

### Summary Tests

```r
test_that("summary returns correct structure when data loaded", {
  store <- DataStore$new()
  
  summary <- store$summary()
  
  expect_type(summary, "list")
  expect_true("message" %in% names(summary))
  expect_true("rows" %in% names(summary))
  expect_true("cols" %in% names(summary))
  expect_true("numeric_means" %in% names(summary))
  expect_equal(summary$rows, 32)
  expect_equal(summary$cols, 12)
})

test_that("summary handles numeric means correctly", {
  store <- DataStore$new()
  
  summary <- store$summary()
  
  expect_type(summary$numeric_means, "double")
  expect_true("mpg" %in% names(summary$numeric_means))
  expect_true("hp" %in% names(summary$numeric_means))
  expect_true(all(!is.na(summary$numeric_means)))
})
```

## Test Utilities

### Helper Functions

```r
# tests/testthat/helpers.R
# Custom test helpers and setup
```

### Test Data Fixtures

```r
# tests/testthat/fixtures/mtcars.R
# Pre-built test data if needed
```

### Shiny Test Configuration

```r
# tests/testthat/helper-shinytest2.R
# Helper functions for ShinyTest2 tests
```

## Test Execution

### Run All Tests
```r
# In R console:
devtools::test()

# Or via RStudio
# Build → Test Package
```

### Run Specific Test File
```r
# Run DataStore tests only
testthat::test_file("tests/testthat/test-DataStore.R")
```

### Check Coverage
```r
# Generate coverage report
coverage <- covr::package_coverage()
covr::report(coverage)
```

## Test Organization

```
tests/
├── testthat.R              # Test runner config
├── testthat/
│   ├── test-DataStore.R    # R6 class tests (60+ tests)
│   ├── test-mod_table.R    # Module tests
│   ├── test-utils.R        # Utility function tests
│   ├── test-shinytest2.R   # Shiny UI tests
│   ├── helpers.R           # Helper functions
│   ├── helper-shinytest2.R # ShinyTest2 config
│   ├── fixtures/
│   │   └── mtcars.R        # Test data fixtures
│   └── _snaps/
│       └── windows-4.5/    # Snapshot tests
│           └── shinytest2/
```

## Testing Principles

1. **Determinism**: No random data, consistent results every run
2. **Isolation**: Each test independent, creates fresh DataStore
3. **Integration**: Real DuckDB, not mocks
4. **Comprehensive**: Happy paths + edge cases + error conditions
5. **Cleanup**: `rm()` and `gc()` after DB operations
6. **Documentation**: Test names explain what they verify
7. **Arrange-Act-Assert**: Clear structure within each test

## Key Test Patterns

**Pattern 1: Fresh Instance**
```r
test_that("...", {
  store <- DataStore$new()  # Fresh for each test
  # ... test ...
  rm(store)
  gc()
})
```

**Pattern 2: State Verification**
```r
test_that("...", {
  # Arrange
  store <- DataStore$new()
  original_copy <- store$original
  
  # Act
  store$update_cell(1, "mpg", 999)
  
  # Assert
  expect_equal(store$data[1, "mpg"], 999)
  expect_equal(store$original, original_copy)
})
```

**Pattern 3: Error Handling**
```r
test_that("...", {
  store <- DataStore$new()
  
  expect_error(
    store$update_cell(row = 999, col = "mpg", value = 20),
    "Row index out of bounds"
  )
})
```

**Pattern 4: DB Integration**
```r
test_that("...", {
  store <- DataStore$new()
  store$update_cell(1, "mpg", 88.8)
  store$save()
  
  # Verify in DB
  db_data <- DBI::dbReadTable(store$con, "mtcars")
  expect_equal(db_data[1, "mpg"], 88.8)
  
  rm(store)
  gc()
})
```

## Coverage Target

Current coverage: **60+ unit tests**
- Initialization: 4 tests
- Immutability: 2 tests
- Cell updates: 8 tests
- Revert: 10+ tests
- Save: 15+ tests
- Summary: 3 tests
- Error conditions: 12+ tests
- Total: ~60 tests

**Coverage Score**: Estimated 85-90% of critical paths

## Summary

The testing architecture provides:
- **Confidence**: Comprehensive coverage of R6 business logic
- **Regression Prevention**: Existing behavior codified as tests
- **Documentation**: Tests serve as behavioral specification
- **Maintainability**: Isolated, deterministic tests are easy to modify

Key principle: **Test the behavior you care about; test error conditions you must prevent.**
