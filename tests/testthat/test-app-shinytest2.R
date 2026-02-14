test_that("app launches with default values", {
  app <- start_app()
  app$wait_for_idle(150)
  app$wait_for_value(output = "table-table", timeout = 10000)
  app$wait_for_idle(150)
  app$expect_values(name = "app-launches")
  app$expect_screenshot(name = "app-launches")
  app$stop()
})
