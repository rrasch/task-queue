#!/usr/bin/env python3

from glob import glob
from pathlib import Path
from pprint import pformat, pprint
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
    level = logging.DEBUG
    logging.basicConfig(format="%(levelname)s: %(message)s", level=level)
    logging.getLogger("pika").setLevel(logging.WARNING)

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
        "AND j.state = 'pending' "
        "ORDER BY j.job_id DESC "
    )
    cursor.execute(query)

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

    if not os.path.isfile(hpc_config["dbfile"]):
        print(f"dbfile {hpc_config['dbfile']} doesn't exist.")
    dbconn = sqlite3.connect(hpc_config["dbfile"])
    cursor = dbconn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS jobs (
            job_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
            slurm_id INTEGER,
            output TEXT NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('pending', 'running', 'done'))
        )
    """
    )

    # delivery_mode=pika.DeliveryMode.Persistent
    delivery_mode = 2

    for request in requests:
        result = cursor.execute(
            f"SELECT job_id FROM jobs WHERE job_id = {request['job_id']}"
        )
        row = result.fetchone()
        if row:
            continue

        body = json.dumps(request, indent=4)
        logging.debug("body: %s", pformat(body))
        channel.basic_publish(
            exchange="",
            routing_key=hpc_config["queue_name"],
            body=body,
            properties=pika.BasicProperties(delivery_mode=delivery_mode),
        )

        cursor.execute(
            f"""
            INSERT INTO jobs (job_id, output, state)
            VALUES ({request['job_id']}, '{request['job_id']}', 'pending')
            """
        )

    mqconn.close()
    dbconn.commit()
    dbconn.close()


if __name__ == "__main__":
    main()
