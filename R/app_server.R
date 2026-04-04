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
  # ===== AUTHENTICATION LAYER =====
  is_authenticated <- shiny::reactiveVal(FALSE)
  
  # Load users from database
  db_config <- get_golem_config("database")
  db_path <- validate_db_path(subdir = db_config$path, filename = db_config$name)
  con_auth <- establish_duckdb_connection(db_path, read_only = TRUE)
  
  users_db <- tryCatch({
    DBI::dbGetQuery(con_auth, "SELECT username, password_hash, role FROM users WHERE is_active = 1")
  }, error = function(e) {
    cli::cli_warn("Failed to load users: {conditionMessage(e)}")
    data.frame(username = character(), password_hash = character(), role = character())
  })
  
  DBI::dbDisconnect(con_auth)
  
  # Initialize error message reactive
  error_msg <- reactiveVal("")
  
  # Render error message output
  output$auth_error_msg <- renderText(error_msg())
  
  # Render login or main app based on auth status
  output$auth_ui <- shiny::renderUI({
    if (is_authenticated()) {
      # Authenticated - show main app
      shinyjs::show("main_app_container")
      shinyjs::addClass("html", "shiny-busy")
    } else {
      # Not authenticated - show login form
      shinyjs::hide("main_app_container")
      div(
        class = "container mt-5",
        style = "max-width: 400px;",
        div(
          class = "card",
          div(
            class = "card-body",
            h3("Submission Editor & Reviewer"),
            p("Secure multi-user workflow", class = "text-muted"),
            br(),
            
            div(
              class = "mb-3",
              tags$label("Username", `for` = "username", class = "form-label"),
              tags$input(
                id = "username",
                type = "text",
                class = "form-control",
                placeholder = "Enter username",
                required = NA  
              )
            ),
            
            div(
              class = "mb-3",
              tags$label("Password", `for` = "password", class = "form-label"),
              tags$input(
                id = "password",
                type = "password",
                class = "form-control",
                placeholder = "Enter password",
                required = NA
              )
            ),
            
            div(
              id = "auth_error",
              class = "alert alert-danger d-none",
              role = "alert",
              shiny::textOutput("auth_error_msg")
            ),
            
            shiny::actionButton(
              "login_btn",
              "Login",
              class = "btn-primary w-100",
              style = "width: 100%; display: block;"
            )
          )
        )
      )
    }
  })
  
  # Handle login button click
  shiny::observeEvent(input$login_btn, ignoreInit = TRUE, {
    username <- input$username
    password <- input$password
    
    tryCatch({
      # Validate input
      if (is.null(username) || username == "") {
        error_msg("Username is required")
        shinyjs::removeClass("auth_error", "d-none")
        return()
      }
      
      if (is.null(password) || password == "") {
        error_msg("Password is required")
        shinyjs::removeClass("auth_error", "d-none")
        return()
      }
      
      # Find user
      user_row <- users_db[users_db$username == username, ]
      
      if (nrow(user_row) == 0) {
        error_msg("Invalid username or password")
        shinyjs::removeClass("auth_error", "d-none")
        return()
      }
      
      # Verify password (assuming bcrypt hashed)
      stored_hash <- user_row$password_hash[1]
      
      # Check if password matches hash using bcrypt
      password_match <- bcrypt::checkpw(password, stored_hash)
      
      if (!password_match) {
        error_msg("Invalid username or password")
        shinyjs::removeClass("auth_error", "d-none")
        return()
      }
      
      # Authentication successful
      error_msg("")  # Clear error
      shinyjs::addClass("auth_error", "d-none")
      session$userData$username <- user_row$username[1]
      session$userData$user_id <- which(users_db$username == user_row$username[1])
      session$userData$user_role <- user_row$role[1]
      is_authenticated(TRUE)
    }, error = function(e) {
      error_msg(paste("Login error:", conditionMessage(e)))
      shinyjs::removeClass("auth_error", "d-none")
    })
  })
  
  # Only proceed with main app logic if authenticated
  shiny::observe({
    req(is_authenticated())
    
    # ===== Reactive user values =====
    user_id <- reactive({
      session$userData$user_id %||% NA
    })

    user_role <- reactive({
      session$userData$user_role %||% "Guest"
    })

    user_name <- reactive({
      session$userData$username %||% "Unknown"
    })

    # ===== Get database connection =====
    con <- reactive({
      establish_duckdb_connection(db_path, read_only = FALSE)
    })

    # ===== Initialize services (singletons per session, stored in session$userData) =====
    # Note: Services are initialized once per Shiny session and stored session-scoped (not package-scoped)
    if (is.null(session$userData$audit_service)) {
      session$userData$audit_service <- AuditService$new(isolate(con()))
    }
    if (is.null(session$userData$user_auth)) {
      session$userData$user_auth <- UserAuth$new(isolate(con()))
    }
    if (is.null(session$userData$submission_service)) {
      session$userData$submission_service <- SubmissionService$new(
        isolate(con()), 
        session$userData$audit_service, 
        access_control
      )
    }
    
    # Create local references for convenience
    audit_service <- session$userData$audit_service
    user_auth <- session$userData$user_auth
    submission_service <- session$userData$submission_service

    # ===== Log login event =====
    tryCatch({
      if (!is.na(isolate(user_id()))) {
        audit_service$log_event(
          event_type = "LOGIN",
          user_id = isolate(user_id())
        )
      }
    }, error = function(e) {
      cli::cli_warn("Failed to log login event: {conditionMessage(e)}")
    })

    # ===== Log logout on session end =====
    session$onSessionEnded(function() {
      tryCatch({
        if (!is.na(isolate(user_id()))) {
          audit_service$log_event(
            event_type = "LOGOUT",
            user_id = isolate(user_id())
          )
        }
      }, error = function(e) {
        # Silently fail on logout (connection may be closing)
      })
    })

    # ===== Initialize DataStore =====
    store <- get_cached_store()
    store_reactive <- reactiveVal(store)
    store_trigger <- reactiveVal(0)

    # ===== Call table module (Editor UI) =====
    mod_table_server(
      "table",
      store_reactive = store_reactive,
      store_trigger = store_trigger,
      user_id = user_id,
      user_role = user_role,
      submission_service = submission_service,
      con = con
    )

    # ===== Call review module (Reviewer UI, conditional) =====
    # Only render if user is Reviewer or Admin
    shiny::observe({
      role <- user_role()
      if (role %in% c("Reviewer", "Admin")) {
        mod_review_server(
          "review",
          con = con,
          user_id = user_id,
          user_role = user_role,
          submission_service = submission_service
        )
      }
    })

    shinyjs::hide("page-loading-spinner")
  })
}
