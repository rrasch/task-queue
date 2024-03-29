#!/usr/bin/python3

import os.path
import pika
import subprocess
import tqcommon


def main():
    env = tqcommon.get_env()
    conf_file = f"/content/{env}/rstar/etc/task-queue.sysconfig"

    if os.path.exists(conf_file):
        process = subprocess.run(
            f"unset MQHOST && source {conf_file} && echo $MQHOST",
            stdout=subprocess.PIPE,
            shell=True,
            universal_newlines=True,
            check=True,
        )
        mqhost = process.stdout.strip()
        if not mqhost:
            mqhost = "localhost"
    else:
        mqhost = "localhost"

    pika_conn_params = pika.ConnectionParameters(host=mqhost)
    connection = pika.BlockingConnection(pika_conn_params)
    channel = connection.channel()

    queue = channel.queue_declare(
        queue="task_queue", durable=True, arguments={"x-max-priority": 10}
    )

    print(queue.method.message_count)


if __name__ == "__main__":
    main()
