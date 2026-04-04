#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_ui <- function(request) {
  tagList(
    shinyjs::useShinyjs(),
    
    # Conditional UI based on authentication
    shiny::uiOutput("auth_ui"),
    
    # Hidden main app UI (shown after login)
    shinyjs::hidden(
      div(
        id = "main_app_container",
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

          bslib::nav_spacer(),
          bslib::nav_panel(
            title = "Home",
            value = "home",

            strong(h1("ADaM ADSL Dataset")),
            p("Interactive data table with real-time editing"),
            mod_table_ui("table")
          ),

          # NEW: Review tab (conditionally shown for Reviewers)
          bslib::nav_panel(
            title = "Review Submissions",
            value = "review",
            mod_review_ui("review")
          ),

          bslib::nav_panel(
            title = "Analytics",
            value = "analytics"
          ),

          bslib::nav_panel(
            title = "Settings",
            value = "settings"
          )
        )
      )
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
  )
}
