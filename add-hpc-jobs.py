#!/usr/bin/env python3

from glob import glob
from pathlib import Path
from pprint import pprint
import MySQLdb
import argparse
import configparser
import errno
import json
import os
import pika
import re
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
                }
            )
    else:
        files = [input_path]
        requests = [
            {
                "input": req["input_path"],
                "output": req["output_path"],
                "args": req["extra_args"],
            }
        ]
    return requests


def main():
    myconfig = tqcommon.get_myconfig()
    sysconfig = tqcommon.get_sysconfig()

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
        queue=queue_name, durable=True, arguments={"x-max-priority": 10}
    )

    print(f"Queue {queue_name} message count: {queue.method.message_count}")

    cursor = dbconn.cursor()
    query = (
        "SELECT cmd_line, request "
        "FROM batch b, job j "
        "WHERE b.batch_id = j.batch_id "
        "AND j.state = 'pending' "
        "ORDER BY b.batch_id DESC "
    )
    cursor.execute(query)

    requests = []

    # Fetch the results
    for cmd_line, request in cursor:
        req = json.loads(request)
        if not (req["class"] == "video" and req["operation"] == "transcode"):
            continue
        requests.extend(gen_vid_requests(req))

    cursor.close()
    dbconn.close()

    # delivery_mode=pika.DeliveryMode.Persistent
    delivery_mode = 2

    for request in requests:
        body = json.dumps(request, indent=4)
        print(body)
        channel.basic_publish(
            exchange="",
            routing_key=queue_name,
            body=body,
            properties=pika.BasicProperties(delivery_mode=delivery_mode),
        )

    mqconn.close()


if __name__ == "__main__":
    main()
