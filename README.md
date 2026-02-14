# editable <img src="inst/app/www/favicon.ico" align="right" height="138" />

> Interactive Excel-Style Data Editor

[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- [![R-CMD-check](https://github.com/Ramdhadage/editable/workflows/R-CMD-check/badge.svg)](https://github.com/Ramdhadage/editable/actions) -->

---

## Overview

**editable** is a feature-rich table editing solution for R Shiny that combines the flexibility of Microsoft Excel with real-time updates, change tracking, and database synchronization. Built on a robust architecture using R6 classes, DuckDB, and custom htmlwidgets, it provides enterprise-grade data editing capabilities within your Shiny applications.

### Key Features

- **📊 Excel-Like Interface** - Familiar spreadsheet experience with HandsOnTable integration
- **💾 Database Persistence** - Seamless DuckDB backend for reliable data storage
- **🔄 Change Tracking** - Built-in undo/revert functionality for data safety
- **🧩 Modular Architecture** - Reusable Shiny modules for rapid development
- **⚡ Real-Time Updates** - Instant UI feedback with reactive state management
- **🎯 Type Safety** - Column-level validation and type coercion
- **📈 Data Summaries** - Automatic statistical summaries for numeric columns
- **🏗️ Production-Ready** - Built with Golem framework for scalability

---

## Installation

### From GitHub

```r
# Install development version
remotes::install_github("Ramdhadage/editable")
```
---

## Quick Start

### Basic Usage

```r
library(editable)

# Launch the application
run_app()
```

### Minimal Example

```r
library(shiny)
library(editable)

ui <- fluidPage(
  titlePanel("Data Editor"),
  mod_table_ui("editor")
)

server <- function(input, output, session) {
  # Initialize data store
  store <- get_cached_store()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)
  # Call the table module
  mod_table_server("editor", store_reactive, store_trigger)
}

shinyApp(ui, server)
```

---

## Architecture

### System Design

```
┌─────────────────────────────────────────────────────────────┐
│                     Shiny Application                        │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   app_server()                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │            DataStore (R6 Class)                  │  │  │
│  │  │  • Database Connection Management                │  │  │
│  │  │  • State Management (data + original)            │  │  │
│  │  │  • CRUD Operations                               │  │  │
│  │  │  • Data Validation                               │  │  │
│  │  │  • Change Tracking                               │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                        ↓                                │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │         mod_table_server("table", store)         │  │  │
│  │  │  • Widget Rendering                              │  │  │
│  │  │  • Event Handling                                │  │  │
│  │  │  • Reactive Updates                              │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                            ↓                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Custom HTMLWidget (hotwidget)             │  │
│  │  • HandsOnTable Integration                            │  │
│  │  • Cell Editing Events                                 │  │
│  │  • Data Synchronization                                │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
                  ┌──────────────────┐
                  │  DuckDB Backend  │
                  │  • Data Storage  │
                  │  • Transactions  │
                  └──────────────────┘
```

### Component Overview

#### 1. DataStore (R6 Class)

The `DataStore` class provides enterprise-grade data management:

```r
store <- DataStore$new()

# Access data
current_data <- store$data
original_data <- store$original

# Update cells
store$update_cell(row = 5, col = "mpg", value = 15000)

# Revert changes
store$revert()

# Get summary statistics
summary_stats <- store$summary()

# Save to database
store$save()
```

#### 2. Table Module

Reusable Shiny module for rapid integration:

```r
# UI
mod_table_ui("my_editor")

# Server
mod_table_server("my_editor", data_store)
```

#### 3. Custom HTMLWidget

Powered by HandsOnTable for rich editing experiences:

- Cell-level editing
- Column type formatting
- Keyboard navigation
- Copy/paste support
- Contextual menus

---

## Advanced Features

```

### Change Tracking

```r


# Get list of changed cells
changes <- store$get_modified_count()

# Revert to original state
store$revert()
```

### Database Persistence

```r
# Save changes back to DuckDB
result <- store$save()

if (result$success) {
  showNotification("Data saved successfully!", type = "message")
} else {
  showNotification(result$error, type = "error")
}
```

---

## Use Cases

### 1. **Data Entry Applications**
Replace manual data entry with an intuitive spreadsheet interface for data collection and management.

### 2. **Database Frontends**
Provide non-technical users with an Excel-like interface to view and edit database tables.

### 3. **ETL Workflows**
Enable data cleaning and transformation through an interactive interface before loading into production systems.

### 4. **Collaborative Data Editing**
Build multi-user applications where teams can edit shared datasets with change tracking.

### 5. **Configuration Management**
Manage application configurations, lookup tables, and reference data through an editable interface.

### 6. **Financial Modeling**
Create interactive financial models with spreadsheet-style data input and real-time calculations.

---

## Configuration

### Application Settings

Edit `inst/golem-config.yml` to customize:

```yaml
default:
  golem_name: editable
  golem_version: 0.1.0
  app_prod: no
  
production:
  app_prod: yes
  db_path: "/var/data/production.duckdb"
  
development:
  app_prod: no
  db_path: "inst/extdata/mtcars.duckdb"
```
---

## Package Structure

```
editable/
├── R/
│   ├── app_server.R          # Main Shiny server logic
│   ├── app_ui.R              # Main Shiny UI
│   ├── DataStore.R           # R6 data management class
│   ├── mod_table.R           # Table module
│   ├── hotwidget.R           # HTMLWidget wrapper
│   └── utils.R               # Utility functions
├── inst/
│   ├── app/www/              # Static assets
│   ├── extdata/              # Sample data
│   ├── htmlwidgets/          # Widget JavaScript/CSS
│   └── golem-config.yml      # App configuration
├── tests/
│   └── testthat/             # Unit tests
├── man/                      # Documentation
├── DESCRIPTION               # Package metadata
├── NAMESPACE                 # Exported functions
└── README.md                 # This file
```

---

## Development

### Running Tests

```r
# Run all tests
devtools::test()

# Run specific test file
testthat::test_file("tests/testthat/test-DataStore.R")

# Test coverage
covr::package_coverage()
```

### Building Documentation

```r
# Generate Rd files from roxygen comments
devtools::document()

# Build pkgdown site
pkgdown::build_site()
```

### Running the App Locally

```r
# Load package in development
devtools::load_all()

# Run app
run_app()

# Or with specific configuration
golem::run_dev()
```

---

## API Reference

### DataStore Class

| Method | Description |
|--------|-------------|
| `new(db_path, table_name)` | Initialize new DataStore instance |
| `update_cell(row, col, value)` | Update single cell value |
| `revert()` | Revert all changes to original state |
| `save()` | Persist changes to database |
| `summary()` | Calculate summary statistics |
| `is_modified()` | Check if data has been changed |
| `get_changes()` | Get list of all modifications |

### Shiny Modules

| Function | Type | Description |
|----------|------|-------------|
| `mod_table_ui(id)` | UI | Table editor module UI |
| `mod_table_server(id, store)` | Server | Table editor module server |

### Utility Functions

| Function | Description |
|----------|-------------|
| `validate_db_path(path)` | Validate database file path |
| `coerce_value(value, type)` | Type-safe value coercion |
| `calculate_column_means(data)` | Calculate numeric column means |

---

## Roadmap

### Version 0.2.0 (Planned)
- [ ] Excel file import/export
- [ ] Advanced filtering and sorting
- [ ] Conditional formatting
- [ ] Formula support
- [ ] Multi-table support

### Version 0.3.0 (Future)
- [ ] Real-time collaboration
- [ ] Version history
- [ ] User permissions
- [ ] Audit logging
- [ ] API endpoints

---

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

1. Clone the repository
```bash
git clone https://github.com/Ramdhadage/editable.git
cd editable
```

2. Install dependencies
```r
renv::restore()
```

3. Run tests
```r
devtools::test()
```

4. Submit a pull request

---

## Support

- **Issues**: [GitHub Issues](https://github.com/Ramdhadage/editable/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Ramdhadage/editable/discussions)
- **Email**: ram.dhadage123@gmail.com

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Citation

If you use this package in your research, please cite:

```bibtex
@software{editable2025,
  author = {Dhadage, Ramnath},
  title = {editable: Interactive Excel-Style Data Editor},
  year = {2025},
  url = {https://github.com/Ramdhadage/editable}
}
```

---

## Acknowledgments

Built with:
- [Shiny](https://shiny.rstudio.com/) - Web application framework
- [Golem](https://thinkr-open.github.io/golem/) - Shiny app development framework
- [DuckDB](https://duckdb.org/) - High-performance analytical database
- [HandsOnTable](https://handsontable.com/) - JavaScript data grid component
- [R6](https://r6.r-lib.org/) - Encapsulated object-oriented programming

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/editable">Ramnath Dhadage</a>
</p>
