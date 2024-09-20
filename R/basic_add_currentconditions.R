# install.packages("RPostgres")
# install.packages("DBI")


library(DBI)

db <- "postgres"
db_host <- "localhost"
db_port <- "5433" # You can use 5432 by default
db_user <- "postgres"
db_pass <- "default"

conn <- dbConnect(
  RPostgres::Postgres(),
  dbname = db,
  host = db_host,
  port = db_port,
  user = db_user,
  password = db_pass
)

print(conn)

current <- read.csv("data/StationInformation.csv")

dbWriteTable(conn, name = "current_conditions", value = current, overwrite = TRUE)

dbListTables(conn)




query <- sprintf("SELECT * FROM current_conditions")
df <- dbGetQuery(conn, query)
