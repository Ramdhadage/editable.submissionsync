.datastore_cache <- NULL
.datastore_init_time <- Sys.time()
.cache_env <- new.env()
#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny shinymanager
#' @noRd
app_server <- function(input, output, session) {
  res_auth <- secure_server(
    check_credentials = check_credentials(credentials)
  )
  current_user <- reactive({
    req(res_auth$user)
    res_auth$user
  })
  store <- get_cached_store()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)

  output$logs_panel <- renderUI({
    store_trigger()
    entries <- store_reactive()$get_audit_log()

    if (length(entries) == 0) {
      div(class = "text-muted small", "No activity yet.")
    } else {
      div(
        class = "d-flex flex-column gap-2",
        lapply(entries, function(entry) {
          div(
            class = "border rounded p-2 bg-light small font-monospace",
            entry
          )
        })
      )
    }
  })

  mod_table_server("table", store_reactive, store_trigger, current_user)
  shinyjs::hide("page-loading-spinner")
}
