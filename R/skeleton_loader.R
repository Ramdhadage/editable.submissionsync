#' Skeleton Loading UI for Progressive Enhancement
#'
#' @description
#' APPROACH #3: Implement skeleton UI that renders immediately while actual
#' data loads in the background. This creates the perception of faster loading
#' even though the same amount of work is happening.
#'
#' Key principle: User sees *something* immediately, not blank page
#'
#' @keywords internal
#'
#' @return HTML tags for skeleton loader

skeleton_loading_ui <- function() {
  # Simple CSS-based skeleton that loads in < 1ms
  shiny::tags$style(shiny::HTML("
    .skeleton-pulse {
      background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
      background-size: 200% 100%;
      animation: pulse 1.5s infinite;
    }
    
    @keyframes pulse {
      0% { background-position: 200% 0; }
      100% { background-position: -200% 0; }
    }
    
    .skeleton-table {
      height: 400px;
      border-radius: 4px;
      margin-bottom: 16px;
    }
    
    .skeleton-summary {
      height: 80px;
      border-radius: 4px;
      margin-bottom: 12px;
    }
    
    .skeleton-text {
      height: 24px;
      border-radius: 4px;
      margin-bottom: 8px;
      width: 60%;
    }
    
    /* Hide skeleton when real content loads */
    .skeleton-hidden {
      display: none;
    }
  "))
}

#' Skeleton Content Placeholder
#'
#' @description
#' Shows immediately while Handsontable and actual data initialize
#'
#' @keywords internal
#'
#' @return HTML showing skeleton placeholder

skeleton_content <- function(id) {
  ns <- shiny::NS(id)
  
  shiny::tagList(
    # CSS animations (loaded first, no JS needed)
    skeleton_loading_ui(),
    
    # Minimal layout structure that matches final design
    shiny::div(
      class = "skeleton-content",
      
      # Table skeleton
      shiny::div(
        class = "skeleton-table skeleton-pulse",
        style = "height: 500px; margin-bottom: 16px;"
      ),
      
      # Summary skeleton
      shiny::div(
        class = "skeleton-summary skeleton-pulse",
        style = "height: 250px; min-width: 150px;"
      )
    )
  )
}

#' JavaScript to Replace Skeleton After Load
#'
#' @description
#' When actual content loads, fade out skeleton and show real content.
#' This creates smooth visual transition.
#'
#' @keywords internal
#'
#' @return HTML script tag

skeleton_replacement_script <- function(id) {
  ns_id <- paste0(id, "-1")  # Shiny namespace pattern
  
  shiny::tags$script(shiny::HTML(sprintf("
    // Wait for Shiny to initialize
    $(document).on('shiny:connected', function() {
      var skeletonContent = document.querySelector('.skeleton-content');
      if (skeletonContent) {
        // Fade out skeleton
        $(skeletonContent).fadeOut(300, function() {
          $(this).addClass('skeleton-hidden');
        });
      }
    });
    
    // Also trigger when real content is ready
    $(document).on('shiny:value', function(event) {
      var skeletonContent = document.querySelector('.skeleton-content');
      if (skeletonContent && event.name === '%s') {
        $(skeletonContent).fadeOut(300, function() {
          $(this).addClass('skeleton-hidden');
        });
      }
    });
  ", ns_id)))
}
