package main


import (
	"database/sql"
	_ "github.com/go-sql-driver/mysql"
	"fmt"
	"os"
	"github.com/go-ini/ini"
)

func main() {

	myConfigFile := "/content/prod/rstar/etc/my-taskqueue.cnf"

	cfg, err := ini.Load(myConfigFile)

	if err != nil {
        fmt.Printf("Fail to read file: %v", err)
        os.Exit(1)
    }

	dbuser := cfg.Section("client").Key("user").String()
	dbpass := cfg.Section("client").Key("password").String()
	dbhost := cfg.Section("client").Key("host").String()
	dbname := cfg.Section("client").Key("database").String()

	dsn := fmt.Sprintf("%s:%s@%s/%s", dbuser, dbpass, dbhost, dbname)
	fmt.Println("dsn: ", dsn)

	db, err := sql.Open("mysql", dsn)

	rows, err := db.Query("SELECT * FROM batch b, job j
	                       WHERE b.batch_id = j.batch_id")


	// Get column names
	columns, err := rows.Columns()

	// Make a slice for the values
	values := make([]sql.RawBytes, len(columns))


}


