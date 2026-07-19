#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_ui <- function(request) {
  tagList(
    shinyjs::useShinyjs(),
    div(
      id = "page-loading-spinner",
      class = "page-loading-overlay",
      div(
        class = "page-loading-container",
        img(
          src = "https://github.com/Ramdhadage/editable.submissionsync/blob/main/inst/app/www/custom.gif?raw=true",
          alt = "Loading...",
          class = "page-loading-gif"
        ),
        p("Loading application...", class = "page-loading-text")
      )
    ),
    bslib::page_navbar(
      title = "Data Explorer",
      id = "navbar",
      theme = bslib::bs_theme(version = 5),
      fillable = TRUE,
      bslib::nav_spacer(),
      bslib::nav_panel(
        value = "home",
        title = bslib::tooltip(bsicons::bs_icon("house-door", size = "2.5em"), "Home", placement = "bottom"),
        strong(h1("ADaM ADSL Dataset")),
        p("Interactive data table with real-time editing"),
        mod_table_ui("table")
      ),
      bslib::nav_panel(
        title = bslib::tooltip(bsicons::bs_icon("bar-chart-line", size = "2.5em"), "Analytics", placement = "bottom"),
        value = "analytics"
      ),
      bslib::nav_panel(
        title = bslib::tooltip(bsicons::bs_icon("gear", size = "2.5em"), "Settings", placement = "bottom"),
        value = "settings"
      ),
      bslib::nav_panel(
        title = bslib::tooltip(bsicons::bs_icon("journal-text", size = "2.5em"), "Logs", placement = "bottom"),
        value = "settings"
      ),
    )
  )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function() {
  add_resource_path(
    "www",
    app_sys("app/www")
  )

  tags$head(
    favicon(),
    bundle_resources(
      path = app_sys("app/www"),
      app_title = "Interactive Excel-Style Data Editor"
    )
    # Add here other external resources
    # for example, you can add shinyalert::useShinyalert()
  )
}
