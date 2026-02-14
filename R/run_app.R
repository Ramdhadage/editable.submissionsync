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
      ui = app_ui,
      server = app_server,
      onStart = onStart,
      options = merged_options,
      enableBookmarking = enableBookmarking,
      uiPattern = uiPattern
    ),
    golem_opts = list(...)
  )
}
