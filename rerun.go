package main


import (
	"database/sql"
	_ "github.com/go-sql-driver/mysql"
	"fmt"
	"os"
	"os/exec"
	"io/ioutil"
	"github.com/go-ini/ini"
)

func InsertJob(req string) {
	file, err := ioutil.TempFile("", "job.*.json")
	if err != nil {
		panic(err)
	}
	defer os.Remove(file.Name())

	fmt.Println(file.Name())

	_, err = file.WriteString(req)
	if err != nil {
		panic(err)
	}

	out, err := exec.Command("add-mb-job",
		"-s", "job:rerun",
		"-j", file.Name()).CombinedOutput()
	if err != nil {
		fmt.Printf("%s", err)
	}
	output := string(out[:])
	fmt.Println(output)
}

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

	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s", dbuser, dbpass, dbhost, dbname)
	fmt.Println("dsn: ", dsn)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		panic(err.Error())
	}

	id := 314

	rows, err := db.Query(fmt.Sprintf(`
			SELECT cmd_line, request
			FROM batch b, job j
			WHERE b.batch_id = j.batch_id
			AND j.batch_id = %d
			AND j.state = 'error'`, id))
	if err != nil {
		panic(err.Error())
	}

	for rows.Next() {
		var cmdLine string
		var req string
		err = rows.Scan(&cmdLine, &req)
		fmt.Println("request: ", req)
		InsertJob(req)
	}

}


