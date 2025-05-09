#!/usr/bin/env python3

import MySQLdb
import argparse
import dateutil.parser
import tqcommon


def update_task_queue_db(job_id, comp_date):
    config = tqcommon.get_myconfig()
    conn = MySQLdb.connect(
        host=config["host"],
        database=config["database"],
        user=config["user"],
        password=config["password"],
        connect_timeout=10,
        autocommit=True,
    )
    cursor = conn.cursor()
    num_rows = cursor.execute(
        """
        UPDATE job
        SET completed = %s,
            state = %s
        WHERE job_id = %s
        """,
        (
            comp_date,
            "error",
            job_id,
        ),
    )
    cursor.close()
    conn.close()
    print(f"{num_rows} rows updated")


def main():
    parser = argparse.ArgumentParser(description="")
    parser.add_argument("job_id", type=int, help="Job id")
    parser.add_argument("comp_date", help="Completion date time")
    args = parser.parse_args()

    comp_date = dateutil.parser.parse(args.comp_date)

    update_task_queue_db(args.job_id, comp_date)


if __name__ == "__main__":
    main()
