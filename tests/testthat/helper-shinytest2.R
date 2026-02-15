# Explicitly load the package to ensure htmlwidgets and other dependencies are available
library(editable.submissionsync)
library(shiny)
start_app <- function(...) {
  app <- shinytest2::AppDriver$new(
    app_dir = system.file("app", package = "editable.submissionsync"),
    load_timeout = 20000,
    variant = shinytest2::platform_variant(),
    expect_values_screenshot_args = FALSE,
    width = 1200,
    height = 1600,
    options = list(test.mode = TRUE)
  )

  app
}
