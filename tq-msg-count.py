#!/usr/bin/python3

import os.path
import pika
import subprocess
import tqcommon


def main():
    config = tqcommon.get_sysconfig()
    mqhost = config.get("mqhost", "localhost")

    pika_conn_params = pika.ConnectionParameters(host=mqhost)
    connection = pika.BlockingConnection(pika_conn_params)
    channel = connection.channel()

    queue = channel.queue_declare(
        queue="task_queue", durable=True, arguments={"x-max-priority": 10}
    )

    print(queue.method.message_count)


if __name__ == "__main__":
    main()
