#!/usr/bin/env python3

from tabulate import tabulate
import configparser
import mysql.connector


def main():
    conf_file = "/content/prod/rstar/etc/my-taskqueue.cnf"

    # Read the config file
    config = configparser.ConfigParser()
    config.read(conf_file)

    # Create a connection object
    cnx = mysql.connector.connect(
        host=config.get("client", "host"),
        database=config.get("client", "database"),
        user=config.get("client", "user"),
        password=config.get("client", "password"),
        connection_timeout=10,
    )

    # Create a cursor and execute a query
    cursor = cnx.cursor()
    query = (
        "SELECT * FROM ("
        "    SELECT job_id, state, request"
        "    FROM job ORDER by job_id"
        "    DESC LIMIT 100"
        ") AS job_query ORDER BY job_id ASC"
    )
    cursor.execute(query)

    rows = []

    # Fetch the results
    for row in cursor:
        rows.append(row)

    # Close the cursor and connection
    cursor.close()
    cnx.close()

    print(tabulate(rows, tablefmt="pretty"))


if __name__ == "__main__":
    main()
