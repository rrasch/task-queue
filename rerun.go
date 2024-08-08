package main


import (
	"database/sql"
	_ "github.com/go-sql-driver/mysql"
	"fmt"
	"os"
	"os/exec"
	"io/ioutil"
	"gopkg.in/ini.v1"
	"flag"
	"regexp"
	"encoding/json"
	"strings"
)


func GetMsgBrokerHost(cmdLine string) string {
	re := regexp.MustCompile(`\s+-m\s+(\w+(\.\w+)*)\s+`)
	found := re.FindStringSubmatch(cmdLine)
	if (found != nil) {
		return found[1]
	} else {
		return "localhost"
	}
}


func InsertJob(req string, host string) {
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
		"-m", host,
		"-s", "job:rerun",
		"-j", file.Name()).CombinedOutput()
	if err != nil {
		fmt.Printf("%s", err)
	}
	output := string(out[:])
	fmt.Println(output)
}


func main() {

	id := flag.Int("b", 0, "Batch id (Required)")
	extraArgs := flag.String("e", "", "Extra arguments")

	flag.Parse()

	if *id < 1 {
		flag.PrintDefaults()
		os.Exit(1)
	}

	hostname, err := os.Hostname()
	if err != nil {
		panic(err.Error())
	}

	env := "prod"
	if strings.HasPrefix(hostname, "d") {
		env = "dev"
	}
	myConfigFile := fmt.Sprintf("/content/%s/rstar/etc/my-taskqueue.cnf", env)

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
	fmt.Println("dsn:", dsn)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		panic(err.Error())
	}

	rows, err := db.Query(fmt.Sprintf(`
			SELECT cmd_line, request
			FROM batch b, job j
			WHERE b.batch_id = j.batch_id
			AND j.batch_id = %d`, *id))
	if err != nil {
		panic(err.Error())
	}

	var request map[string]interface{}

	for rows.Next() {
		var cmdLine string
		var req string
		err = rows.Scan(&cmdLine, &req)
		host := GetMsgBrokerHost(cmdLine)
		fmt.Println("cmdline:", cmdLine)
		fmt.Println("request:", req)
		fmt.Println("mbhost:", host)
		json.Unmarshal([]byte(req), &request)
		if *extraArgs != "" {
			tmp := ""
			if request["extra_args"] != nil {
				tmp += request["extra_args"].(string) + " "
			}
			tmp += *extraArgs
			request["extra_args"] = tmp
			newRequest, _ :=
				json.MarshalIndent(request, "", "    ")
			req = string(newRequest)
		}
		fmt.Println("New request:", req)
		InsertJob(req, host)
	}

}
