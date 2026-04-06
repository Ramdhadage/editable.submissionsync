.datastore_cache <- NULL
.datastore_init_time <- Sys.time()
.cache_env <- new.env()
#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_server <- function(input, output, session) {
  res_auth <- shinymanager::secure_server(
    check_credentials = shinymanager::check_credentials(credentials)
  )
  current_user  <- reactive({ req(res_auth$user);  res_auth$user  })
  store <- get_cached_store()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)
  mod_table_server("table", store_reactive, store_trigger)
  shinyjs::hide("page-loading-spinner")
}
