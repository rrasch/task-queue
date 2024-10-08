#!/usr/bin/env python3

from glob import glob
from pathlib import Path
from pprint import pformat, pprint
from util import is_pos_int
import MySQLdb
import argparse
import configparser
import errno
import json
import logging
import os
import pika
import re
import sqlite3
import sys
import tqcommon


def gen_vid_requests(req):
    requests = []
    if not os.path.exists(req["input_path"]):
        raise FileNotFoundError(
            errno.ENOENT, os.strerror(errno.ENOENT), req["input_path"]
        )
    if os.path.isdir(req["input_path"]):
        files = []
        for ext in ["avi", "mkv", "mov", "mp4"]:
            files.extend(glob(f"{req['input_path']}{os.sep}*_d.{ext}"))
        for file in sorted(files):
            output_base = os.path.join(req["output_path"], Path(file).stem)
            output_base = re.sub(r"_d$", "", output_base)
            requests.append(
                {
                    "input": file,
                    "output": output_base,
                    "args": req["extra_args"],
                    "job_id": req["job_id"],
                }
            )
    else:
        requests = [
            {
                "input": req["input_path"],
                "output": req["output_path"],
                "args": req["extra_args"],
                "job_id": req["job_id"],
            }
        ]
    return requests


def main():
    parser = argparse.ArgumentParser(description="Add video jobs to hpc queue")
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debugging"
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="Don't actually add job, implies --debug",
    )
    parser.add_argument(
        "--create-database", action="store_true", help="Create database"
    )
    parser.add_argument(
        "-s",
        "--job-state",
        default="pending",
        help="Get jobs from task queue in this state, e.g. 'success'",
    )
    parser.add_argument(
        "-l",
        "--limit",
        type=is_pos_int,
        default=100,
        help="Limit jobs added to queue to this number",
    )
    args = parser.parse_args()

    if args.dry_run:
        args.debug = True

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(
        format="%(asctime)s|%(levelname)s: %(message)s",
        datefmt="%m/%d/%Y %I:%M:%S %p",
        level=level,
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    logging.debug(f"args: {args}")

    myconfig = tqcommon.get_myconfig()
    sysconfig = tqcommon.get_sysconfig()
    hpc_config = tqcommon.get_hpc_config()

    queue_name = "hpc_transcode"

    dbconn = MySQLdb.connect(
        host=myconfig["host"],
        database=myconfig["database"],
        user=myconfig["user"],
        password=myconfig["password"],
        connect_timeout=10,
    )

    pika_conn_params = pika.ConnectionParameters(host=sysconfig["mqhost"])
    mqconn = pika.BlockingConnection(pika_conn_params)
    channel = mqconn.channel()

    queue = channel.queue_declare(
        queue=hpc_config["queue_name"],
        durable=True,
        arguments={"x-max-priority": 10},
    )

    logging.debug(
        f"Queue {hpc_config['queue_name']} message count: "
        f"{queue.method.message_count}"
    )

    cursor = dbconn.cursor()
    query = (
        "SELECT j.batch_id, j.job_id, b.cmd_line, j.request "
        "FROM batch b, job j "
        "WHERE b.batch_id = j.batch_id "
        "AND j.state = %s "
        "AND j.request LIKE '%%video%%' "
        "ORDER BY j.job_id DESC "
        "LIMIT %s "
    )
    num_rows = cursor.execute(query, (args.job_state, args.limit))
    logging.debug(f"Num rows: {num_rows}")

    requests = []

    # Fetch the results
    for batch_id, job_id, cmd_line, request in cursor:
        req = json.loads(request)
        req["job_id"] = job_id
        if not (req["class"] == "video" and req["operation"] == "transcode"):
            continue
        requests.extend(gen_vid_requests(req))

    logging.debug("requests:\n%s", pformat(requests))

    cursor.close()
    dbconn.close()

    if args.dry_run:
        sys.exit()

    if not os.path.isfile(hpc_config["dbfile"]):
        sys.exit(f"sqlite database '{hpc_config['dbfile']}' doesn't exist.")
    dbconn = sqlite3.connect(hpc_config["dbfile"])
    cursor = dbconn.cursor()
    if args.create_database:
        cursor.execute("DROP TABLE IF EXISTS jobs")
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                job_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
                slurm_id INTEGER,
                output TEXT,
                state TEXT NOT NULL
                    CHECK (state IN ('pending', 'running', 'done'))
            )
            """
        )

    # delivery_mode=pika.DeliveryMode.Persistent
    delivery_mode = 2

    for request in requests:
        result = cursor.execute(
            "SELECT job_id FROM jobs WHERE job_id = ?", (request["job_id"],)
        )
        row = result.fetchone()
        if row:
            logging.info("job_id %s already in db", request["job_id"])
            continue

        body = json.dumps(request, indent=4)
        logging.info("Adding video request: %s", body)
        channel.basic_publish(
            exchange="",
            routing_key=hpc_config["queue_name"],
            body=body,
            properties=pika.BasicProperties(delivery_mode=delivery_mode),
        )

        cursor.execute(
            f"""
            INSERT INTO jobs (job_id, state)
            VALUES (?, 'pending')
            """,
            (request["job_id"],),
        )

    mqconn.close()
    dbconn.commit()
    dbconn.close()


if __name__ == "__main__":
    main()
