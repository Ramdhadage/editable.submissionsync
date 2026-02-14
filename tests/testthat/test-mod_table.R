# Module Tests for mod_table using testServer
# Testing Strategy: testServer for Shiny module testing

library(shiny)

test_that("mod_table_server initializes with reactiveVal DataStore", {
  with_fresh_mtcars_db()
  # Arrange - Create test DataStore
  store <- DataStore$new()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)
  # Act & Assert
  testServer(mod_table_server, args = list(store_reactive = store_reactive, store_trigger = store_trigger), {
    expect_equal(output$summary_rows, "32")
    expect_equal(output$summary_cols, "12")
    expect_equal(output$summary_mpg, sprintf("%.1f", mean(mtcars[, "mpg"])))
    expect_equal(output$summary_hp, sprintf("%.1f", mean(mtcars[, "hp"])))
    expect_equal(output$summary_modified, "0")

  })
})

test_that("valid table edit updates store and modified count", {
  with_fresh_mtcars_db()
  store <- DataStore$new()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)

  testServer(mod_table_server, args = list(store_reactive = store_reactive, store_trigger = store_trigger), {
    # Simulate JS edit: zero-based row index
    session$setInputs(table_edit = list(row = 0, col = "mpg", value = 30))
    session$setInputs(`_raf_trigger` = 1)
    # expect update applied to store
    expect_equal(as.numeric(store$data[1, "mpg"]), 30)
    expect_equal(store$get_modified_count(), 1)
    expect_equal(output$summary_modified, "1")
  })
})

test_that("save flow calls store$save and resets modified count", {
  with_fresh_mtcars_db()
  store <- DataStore$new()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)

  testServer(mod_table_server, args = list(store_reactive = store_reactive, store_trigger = store_trigger), {
    # make an edit
    session$setInputs(table_edit = list(row = 1, col = "mpg", value = 22))
    session$setInputs(`_raf_trigger` = 1)
    expect_equal(store$get_modified_count(), 1)

    # trigger save modal then confirm save
    session$setInputs(save = 1)
    session$setInputs(`_raf_trigger` = 1)
    session$setInputs(confirm_save = 1)
    session$setInputs(`_raf_trigger` = 1)

    # after save modified counter should be reset
    expect_equal(store$get_modified_count(), 0)
    # original should match data after save
    expect_equal(store$original$mpg[1], store$data$mpg[1])
  })
})

test_that("revert flow calls store$revert and resets modified count", {
  with_fresh_mtcars_db()
  store <- DataStore$new()
  store_reactive <- reactiveVal(store)
  store_trigger <- reactiveVal(0)

  testServer(mod_table_server, args = list(store_reactive = store_reactive, store_trigger = store_trigger), {
    session$setInputs(table_edit = list(row = 1, col = "mpg", value = 10))
    session$setInputs(`_raf_trigger` = 1)
    expect_equal(store$get_modified_count(), 1)

    session$setInputs(revert = 1)
    session$setInputs(`_raf_trigger` = 1)
    # revert resets counter and restores original value
    expect_equal(store$get_modified_count(), 0)
    expect_equal(store$data$mpg[1], store$original$mpg[1])
  })
})
