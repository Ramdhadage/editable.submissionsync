# Contributing to editable

Thank you for your interest in contributing to **editable**! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

---

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please:

- Be respectful and considerate
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Accept responsibility for mistakes
- Prioritize the community's best interests

---

## Getting Started

### Setup Development Environment

1. **Fork and clone the repository**

```bash
git clone https://github.com/Ramdhadage/editable.git
cd editable
```

2. **Install dependencies**

```r
# Using renv for reproducibility
renv::restore()

# Or manually install
install.packages(c("devtools", "testthat", "roxygen2", "pkgdown"))
```

3. **Load the package**

```r
devtools::load_all()
```

4. **Run the app**

```r
run_app()
```

---

## Development Workflow

### Branch Strategy

We use a simplified Git flow:

- `main` - Production-ready code
- `develop` - Integration branch for features
- `feature/feature-name` - New features
- `bugfix/bug-name` - Bug fixes
- `hotfix/issue-name` - Critical production fixes

### Creating a Feature Branch

```bash
# Update your local repository
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feature/amazing-new-feature

# Make your changes and commit
git add .
git commit -m "feat: add amazing new feature"

# Push to your fork
git push origin feature/amazing-new-feature
```

### Commit Message Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

**Examples:**

```
feat(DataStore): add multi-table support

fix(mod_table): resolve cell update race condition

docs(README): update installation instructions

test(utils): add tests for validation functions
```

---

## Coding Standards

### R Style Guide

We follow the [tidyverse style guide](https://style.tidyverse.org/):

**Naming Conventions:**

```r
# Functions: snake_case
calculate_summary_stats <- function(data) { }

# Variables: snake_case
user_input <- "value"

# R6 Classes: PascalCase
DataStore <- R6::R6Class("DataStore")

# Constants: SCREAMING_SNAKE_CASE
MAX_ROWS <- 10000
```

**Code Formatting:**

```r
# Use explicit returns
calculate_mean <- function(x) {
  result <- mean(x, na.rm = TRUE)
  return(result)
}

# Proper spacing
x <- 1 + 2  # Good
x<-1+2      # Bad

# Line length: max 80 characters
# Use line breaks for long function calls
very_long_function_name(
  parameter_one = "value",
  parameter_two = "another_value",
  parameter_three = "yet_another_value"
)
```

**Comments:**

```r
# Single-line comments use #

#' Roxygen documentation for exported functions
#'
#' @param data A data frame to process
#' @param column Column name to analyze
#' @return Summary statistics
#' @export
calculate_stats <- function(data, column) {
  # Implementation details
}
```

### JavaScript Style Guide

For HTMLWidget code:

```javascript
// Use ES6+ syntax
const updateCell = (row, col, value) => {
  // Implementation
};

// Proper error handling
try {
  performOperation();
} catch (error) {
  console.error('Operation failed:', error);
  Shiny.setInputValue('error', error.message);
}

// Document complex logic
/**
 * Handles cell edits and syncs with R
 * @param {number} row - Row index
 * @param {number} col - Column index
 * @param {any} oldValue - Previous value
 * @param {any} newValue - New value
 */
function handleCellEdit(row, col, oldValue, newValue) {
  // Implementation
}
```

---

## Testing Guidelines

### Writing Tests

All new features must include tests. We use `testthat` for R code:

```r
# tests/testthat/test-DataStore.R

test_that("DataStore initializes correctly", {
  store <- DataStore$new(
    db_path = test_path("fixtures/test.duckdb"),
    table_name = "test_table"
  )
  
  expect_s3_class(store, "DataStore")
  expect_s3_class(store, "R6")
  expect_true(!is.null(store$data))
})

test_that("update_cell modifies data correctly", {
  store <- create_test_store()
  
  store$update_cell(row = 1, col = "value", value = 100)
  
  expect_equal(store$data[1, "value"], 100)
  expect_true(store$is_modified())
})
```

### Running Tests

```r
# Run all tests
devtools::test()

# Run specific test file
testthat::test_file("tests/testthat/test-DataStore.R")

# Run with coverage
covr::package_coverage()

# Interactive testing
testthat::test_file("tests/testthat/test-DataStore.R", reporter = "progress")
```

### Test Coverage

- Aim for >80% code coverage
- All exported functions must have tests
- Edge cases and error conditions must be tested

---

## Documentation

### Function Documentation

Use roxygen2 for all exported functions:

```r
#' Update a cell in the data store
#'
#' Modifies a single cell value and tracks the change for potential reversion.
#'
#' @param row Integer. Row index (1-based)
#' @param col Character. Column name or integer column index
#' @param value Any. New value to set (will be coerced to column type)
#'
#' @return Invisibly returns the DataStore object for method chaining
#'
#' @examples
#' store <- DataStore$new("data.duckdb", "my_table")
#' store$update_cell(row = 5, col = "revenue", value = 15000)
#'
#' @export
update_cell <- function(row, col, value) {
  # Implementation
}
```

### Vignettes

For major features, create vignettes:

```r
# Create new vignette
usethis::use_vignette("advanced-features")
```

### README Updates

Update README.md when adding:
- New features
- Breaking changes
- Configuration options
- Examples

---

## Submitting Changes

### Pull Request Process

1. **Ensure all tests pass**

```r
devtools::test()
devtools::check()
```

2. **Update documentation**

```r
devtools::document()
```

3. **Update NEWS.md**

```markdown
# editable 0.2.0

## New Features

* Added multi-table support (#123)
* Implemented Excel import/export (#145)

## Bug Fixes

* Fixed race condition in cell updates (#134)

## Breaking Changes

* `DataStore$new()` now requires `table_name` parameter
```

4. **Create Pull Request**

- Use a clear, descriptive title
- Reference related issues
- Describe changes in detail
- Include screenshots for UI changes
- Check all CI/CD checks pass

**PR Template:**

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## How Has This Been Tested?
Describe testing approach

## Checklist
- [ ] Tests pass locally
- [ ] Documentation updated
- [ ] NEWS.md updated
- [ ] No breaking changes (or documented)
```

### Code Review

- Address all review comments
- Be open to feedback
- Explain design decisions
- Keep discussions focused and professional

---

## Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- `MAJOR.MINOR.PATCH`
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes

### Release Checklist

**Maintainers Only:**

1. Update version in DESCRIPTION
2. Update NEWS.md
3. Run `devtools::check()`
4. Build documentation: `pkgdown::build_site()`
5. Create release on GitHub
6. Submit to CRAN (if applicable)

---

## Need Help?

- **Questions**: Open a [Discussion](https://github.com/Ramdhadage/editable/discussions)
- **Bugs**: Create an [Issue](https://github.com/Ramdhadage/editable/issues)
- **Email**: ram.dhadage123@gmail.com

---

Thank you for contributing to **editable**! 🎉