library(duckdb)
library(haven)
df<- haven::read_sas("inst/extdata/adsl.sas7bdat")
# Check original size
original_size <- object.size(df)
print(paste("Original dataframe size:", format(original_size, units = "MB")))
sas_size <- fs::file_size("inst/extdata/adsl.sas7bdat")
print(paste("SAS file size:", format(sas_size, units = "MB")))
# Convert to DuckDB
 con <- dbConnect(duckdb::duckdb(), dbdir = "inst/extdata/adsl.duckdb", config=list("default_block_size" = "16384"))
 dbWriteTable(con, "adsl", df, overwrite = TRUE)
 dbExecute(con, "VACUUM")
 dbExecute(con, "CHECKPOINT")
 dbDisconnect(con, shutdown = TRUE)
 duckdb_size <- fs::file_size("inst/extdata/adsl.duckdb")
 print(paste("DuckDB file size:", format(duckdb_size, units = "MB")))

