#' Run the Shiny Application
#'
#' @param ... arguments to pass to golem_opts.
#' See `?golem::get_golem_options` for more details.
#' @inheritParams shiny::shinyApp
#'
#' @export
#' @importFrom shiny shinyApp
#' @importFrom golem with_golem_options
#' @importFrom utils modifyList
run_app <- function(
  onStart = NULL,
  options = list(),
  enableBookmarking = NULL,
  uiPattern = "/",
  ...
) {
  apply_shiny_performance_config()

  in_test <- nzchar(Sys.getenv("SHINYTEST_REMOTE"))
  test_options <- if (in_test) list(test.mode = TRUE) else list()

  perf_opts <- get_shiny_server_options()
  merged_options <- modifyList(modifyList(perf_opts, test_options), options)

  with_golem_options(
    app = shinyApp(
      ui = shinymanager::secure_app(
      ui = app_ui,
      enable_admin = TRUE,
      # Login page customisation
      tags_top = tags$div(
        style = "text-align:center; margin-bottom:20px;",
        tags$h3("Welcome", style = "color:#2c3e50; font-weight:700;"),
        tags$p("Please sign in to continue.", style = "color:#7f8c8d;")
      ),
      tags_bottom = tags$div(
        style = "text-align:center; margin-top:20px;
                   font-size:12px; color:#95a5a6;",
        tags$p("Contact your administrator if you have trouble signing in.")
      )
      ),
      server = app_server,
      onStart = onStart,
      options = merged_options,
      enableBookmarking = enableBookmarking,
      uiPattern = uiPattern
    ),
    golem_opts = list(...)
  )
}
