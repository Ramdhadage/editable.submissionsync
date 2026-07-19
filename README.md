# editable.submissionsync <img src="inst/app/www/favicon.png" align="right" height="138" />

> “Audit-Ready Clinical Dataset Review Platform”

[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- [![R-CMD-check](https://github.com/Ramdhadage/editable.submissionsync/workflows/R-CMD-check/badge.svg)](https://github.com/Ramdhadage/editable.submissionsync/actions) -->

---

## Overview

Editable Submission Sync is a Shiny-based application designed to modernize how clinical teams **review, track, and approve dataset changes** during the final stages before regulatory submission.
It introduces a **structured, audit-ready workflow** to replace fragmented processes involving Excel files, email threads, and manual tracking.


### Key Features
- **📊 Excel-Like Interface** - Familiar spreadsheet experience with HandsOnTable integration
- **📜 Full Audit Trail** - Automatically logs User, Field changed, Previous value, New value and Timestamp. Also, provides **complete traceability for audits**
- **🔍 Review and Approval Workflow** - Role-based system: **Editor** → makes changes and **Reviewer** → approves/rejects
- **🔐 Role-Based Access Control** — Secure login with granular permission levels (Viewer, Editor, Reviewer, Admin)
- **💾 Database Persistence** - Seamless DuckDB backend for reliable data storage
- **🔄 Change Tracking** - Built-in undo/revert functionality for data safety
- **🧩 Modular Architecture** - Reusable Shiny modules for rapid development
- **⚡ Real-Time Updates** - Instant UI feedback with reactive state management
- **🎯 Type Safety** - Column-level validation and type coercion
- **📊 Dynamic Visualization** - Generate plots (e.g., swimmer plots) and automatically reflect dataset updates
- **📈 Data Summaries** - Automatic statistical summaries for numeric columns
- **🏗️ Production-Ready** - Built with Golem framework for scalability

---
## 🚀 Live Demo

**Try it now:** [https://ti5syn-ramdhadage.shinyapps.io/editable/](https://ti5syn-ramdhadage.shinyapps.io/editable/)

### Demo Credentials

Choose a role to explore features tailored to your responsibility level:

| Role | Username | Password | Permissions |
|:---|:---|:---|:---|
| **👁️ Viewer** | `viewer` | `Viewer@123` | Read-only |
| **✅ Reviewer** | `reviewer` | `Reviewer@123` | Comment & Approve |
| **✏️ Editor** | `editor` | `Editor@123` | Read, Write & Modify |
| **🔑 Admin** | `admin` | `Admin@123` | Full control |

---

## Installation

### From GitHub

```r
# Install development version
remotes::install_github("Ramdhadage/editable.submissionsync")
```
---

## Quick Start

### Basic Usage

```r
library(editable.submissionsync)

# Launch the application
run_app()
```

### Minimal Example

```r
library(shiny)
library(editable.submissionsync)

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

## Use Cases

| Use Case | Description | Who Benefits |
|---|---|---|
| **Pre-Submission Review** | Consolidate final dataset corrections before regulatory submission | Clinical Data Managers |
| **Change Governance** | Track who changed what and when with immutable audit trail | Compliance Officers |
| **Team Collaboration** | Enable editors to submit changes; reviewers approve/reject with comments | Data Teams |
| **Data Validation** | Catch type mismatches and out-of-range values in real-time | QA/Validation Teams |
| **Regulatory Readiness** | Export audit-ready change logs for FDA/EMA submissions | Regulatory Affairs |

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

## 🚀 Value Proposition

- ✅ Replace Excel + email-based workflows  
- ✅ Ensure **audit-ready traceability**  
- ✅ Reduce errors in final dataset review  
- ✅ Improve collaboration between editors & reviewers  
- ✅ Accelerate submission readiness  


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

## FAQ

**Q: Is this production-ready?**  
A: The core data management and UI are production-grade. Authentication and audit logging are currently at MVP level; they will be hardened before use in regulated environments.

**Q: Can I connect to my existing database?**  
A: Yes. The DuckDB backend can read from PostgreSQL, MySQL, and other sources. See documentation for connection details.

**Q: What's the maximum dataset size?**  
A: Tested to 10M rows in DuckDB. UI performance depends on viewport size; recommend ≤100K rows for browser display.

**Q: How do I export audit logs for compliance?**  
A: Use `store$get_audit_log()` to export change history as CSV/JSON. Full regulatory documentation coming in v0.2.

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
