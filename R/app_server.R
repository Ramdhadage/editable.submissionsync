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
  store <- get_cached_store()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)
  mod_table_server("table", store_reactive, store_trigger)
}
