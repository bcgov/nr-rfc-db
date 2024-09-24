# install.packages("RPostgres")
# install.packages("DBI")


library(DBI)

# setting up the database connection parameters
db <- Sys.getenv("POSTGRES_DB", "postgres")
db_host <- Sys.getenv("POSTGRES_HOST", "localhost")
db_port <- Sys.getenv("POSTGRES_PORT", "5433")
db_user <- Sys.getenv("POSTGRES_USER", "postgres")
db_pass <- Sys.getenv("POSTGRES_PASSWORD", "default")

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

# as a best practice you would be better off, using dbAppendTable so that if the table 
# doesn't exist an error gets raised as the table should have been created by a migration
dbWriteTable(conn, name = "hydro.current_conditions", value = current, overwrite = TRUE)

dbListTables(conn)
query <- sprintf("SELECT * FROM current_conditions")
df <- dbGetQuery(conn, query)
