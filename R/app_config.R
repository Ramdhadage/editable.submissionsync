#' Access files in the current app
#'
#' NOTE: If you manually change your package name in the DESCRIPTION,
#' don't forget to change it here too, and in the config file.
#' For a safer name change mechanism, use the `golem::set_golem_name()` function.
#'
#' @param ... character vectors, specifying subdirectory and file(s)
#' within your package. The default, none, returns the root of the app.
#'
#' @noRd
app_sys <- function(...) {
  system.file(..., package = "editable.submissionsync")
}


#' Read App Config
#'
#' @param value Value to retrieve from the config file.
#' @param config GOLEM_CONFIG_ACTIVE value. If unset, R_CONFIG_ACTIVE.
#' If unset, "default".
#' @param use_parent Logical, scan the parent directory for config file.
#' @param file Location of the config file
#'
#' @noRd
get_golem_config <- function(
  value = NULL,
  config = Sys.getenv(
    "GOLEM_CONFIG_ACTIVE",
    Sys.getenv(
      "R_CONFIG_ACTIVE",
      "default"
    )
  ),
  use_parent = TRUE,
  # Modify this if your config file is somewhere else
  file = app_sys("golem-config.yml")
) {
  config::get(
    value = value,
    config = config,
    file = file,
    use_parent = use_parent
  )
}
#' Get Database Configuration
#'
#' @description
#' Retrieves database configuration from golem-config.yml.
#' This is the {golem} way: centralized, environment-aware configuration.
#'
#' @param config Environment name (default, production, test, etc.)
#'
#' @return List with database configuration
#'
#' @examples
#' \dontrun{
#' db_config <- get_database_config()
#' db_config <- get_database_config("production")
#' }
#' @export
get_database_config <- function(config = Sys.getenv("GOLEM_CONFIG_ACTIVE", "default")) {
  get_golem_config("database", config = config)
}

#' Get Schema Configuration
#'
#' @description
#' Retrieves schema configuration from golem-config.yml.
#'
#' @param config Environment name
#'
#' @return List with schema configuration
#'
#' @examples
#' \dontrun{
#' schema_config <- get_schema_config()
#' }
#' @export
get_schema_config <- function(config = Sys.getenv("GOLEM_CONFIG_ACTIVE", "default")) {
  get_golem_config("schema", config = config)
}

#' Validate Configuration
#'
#' @description
#' Validates that golem-config.yml has required database and schema sections.
#' Called during app initialization to fail-fast on misconfiguration.
#'
#' @param config Environment name
#'
#' @return Invisible TRUE or throws error
#'
#' @keywords internal
validate_golem_config <- function(config = Sys.getenv("GOLEM_CONFIG_ACTIVE", "default")) {
  tryCatch({
    # Validate database section
    db_config <- get_database_config(config)
    checkmate::assert_list(db_config, names = "named")
    checkmate::assert_names(
      names(db_config),
      must.include = c("name", "path")
    )

    # Validate schema section
    schema_config <- get_schema_config(config)
    checkmate::assert_list(schema_config, names = "named", min.len = 1)

    cli::cli_alert_success("Configuration validated: {config}")
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_abort(c(
      "Invalid golem-config.yml configuration",
      "i" = "Environment: {config}",
      "x" = "{conditionMessage(e)}",
      "!" = "Check inst/golem-config.yml structure"
    ))
  })
}
