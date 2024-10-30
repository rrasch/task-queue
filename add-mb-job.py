#!/usr/bin/python3

from pprint import pformat
import MySQLdb
import argparse
import json
import logging
import os
import pika
import sys
import tqcommon
import util


QUEUE_NAME = "task_queue"
EXCHANGE_NAME = "tq_logging"
CHANNEL_MAX = 32
PERSISTENT_DELIVERY_MODE = 2


def usage(parser, msg, brief=True):
    print(msg, file=sys.stderr)
    if brief:
        parser.print_usage(sys.stderr)
    else:
        parser.print_usage(sys.stderr)
    sys.exit(1)


def publish(cursor, channel, task):
    body = json.dumps(task, indent=4)
    query = """
        INSERT INTO job
        (batch_id, request, user_id, state, submitted)
        VALUES (%s, %s, %s, 'pending', NOW())
    """
    num_rows = cursor.execute(query, (task["batch_id"], body, task["user_id"]))

    task["job_id"] = cursor.lastrowid
    logging.debug("job id: %s", task["job_id"])
    body = json.dumps(task, indent=4)
    task.pop("job_id")
    logging.debug("Sending body: %s", pformat(task))

    channel.basic_publish(
        exchange=EXCHANGE_NAME,
        routing_key=f"{QUEUE_NAME}.pending",
        body=body,
        properties=pika.BasicProperties(
            delivery_mode=PERSISTENT_DELIVERY_MODE,
        ),
    )

    channel.basic_publish(
        exchange="",
        routing_key=QUEUE_NAME,
        body=body,
        properties=pika.BasicProperties(
            delivery_mode=PERSISTENT_DELIVERY_MODE,
            priority=task["priority"],
        ),
    )


def get_dir_contents(dirpath):
    return sorted([
        item
        for item in os.listdir(dirpath)
        if os.path.isdir(os.path.join(dirpath, item))
    ])


def validate_filepath(filepath):
    """Validates a filepath and returns it if valid."""
    if not os.path.exists(filepath):
        raise argparse.ArgumentTypeError(f"File not found: '{filepath}'")
    return filepath


def main():
    env = tqcommon.get_env()
    my_conf_file = f"/content/{env}/rstar/etc/my-taskqueue.cnf"
    sysconfig = tqcommon.get_sysconfig()

    parser = argparse.ArgumentParser()
    parser.add_argument("id", nargs="*", help="Digital object identifier")
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose messages"
    )
    parser.add_argument(
        "-t",
        "--test",
        action="store_true",
        help="Test connection to rabbitmq and mysql",
    )
    parser.add_argument(
        "-m",
        "--mqhost",
        default=sysconfig["mqhost"],
        help="hostname for RabbitMQ messaging server (default: %(default)s)",
    )
    parser.add_argument("-r", "--rstar-dir", help="R* (Rstar) directory")
    parser.add_argument(
        "-i",
        "--input-path",
        type=validate_filepath,
        help="input path (directory or file)",
    )
    parser.add_argument(
        "-o",
        "--output-path",
        type=validate_filepath,
        help="output path (directory or file prefix)",
    )
    parser.add_argument(
        "-c",
        "--mysql-config-file",
        type=validate_filepath,
        default=my_conf_file,
        help="mysql config file (default: %(default)s)",
    )
    parser.add_argument(
        "-p",
        "--priority",
        default=0,
        choices=range(11),
        help="message priority (default: %(default)s)",
    )
    parser.add_argument("-s", "--service", help="service, e.g. video:transcode")
    parser.add_argument(
        "-e", "--extra-args", default="", help="extra command line args"
    )
    parser.add_argument(
        "-j",
        "--json-config",
        type=validate_filepath,
        help="json config to pass to job",
    )
    args = parser.parse_args()

    level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        format="%(asctime)s %(levelname)s: %(message)s",
        level=level,
        datefmt="%m/%d/%Y %I:%M:%S %p",
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    logging.debug("sysconfig: %s", sysconfig)

    cmd_line = util.shlex_join([os.path.realpath(sys.argv[0]), *sys.argv[1:]])
    logging.debug(f"cmd line: {cmd_line}")

    if args.test:
        print("Running in test mode.")

    if not args.test:
        if not args.service:
            usage(parser, "You must set -s to define the service.")

        cls, delim, op = args.service.partition(":")

        if not cls or not op:
            usage(
                parser,
                "You must set -s to define service in the format "
                "<class>:<service>,  e.g. audio:transcode",
            )

    mq_conn = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=args.mqhost,
            channel_max=CHANNEL_MAX,
            socket_timeout=3,
        )
    )

    logging.debug(
        "server properties: %s", pformat(mq_conn._impl.server_properties)
    )
    logging.debug(
        "server capabilities: %s", pformat(mq_conn._impl.server_capabilities)
    )

    channel = mq_conn.channel()
    queue = channel.queue_declare(
        queue=QUEUE_NAME,
        durable=True,
        arguments={"x-max-priority": 10},
    )
    logging.debug(
        f"Queue {QUEUE_NAME} message count: {queue.method.message_count}"
    )

    channel.exchange_declare(
        exchange=EXCHANGE_NAME,
        exchange_type="topic",
        durable=True,
    )

    db_conn = MySQLdb.connect(read_default_file=my_conf_file, autocommit=True)
    cursor = db_conn.cursor()

    if args.test:
        sys.exit(0)

    login = os.getlogin()

    query = "INSERT into batch (user_id, cmd_line) VALUES (%s, %s)"
    num_rows = cursor.execute(query, (login, cmd_line))
    batch_id = cursor.lastrowid

    task = {
        "class": cls,
        "operation": op,
        "extra_args": args.extra_args,
        "user_id": os.getlogin(),
        "batch_id": batch_id,
        "state": "pending",
        "priority": args.priority,
    }

    args_dict = vars(args)
    logging.debug("args dict:\n%s", pformat(args_dict))
    for path in ("rstar_dir", "input_path", "output_path"):
        if args_dict[path]:
            task[path] = args_dict[path]

    if args.json_config:
        with open(args.json_config) as f:
            data = json.load(f)
        for k, v in data.items():
            task[k] = v

    logging.debug("task:\n%s", pformat(task))

    if args.rstar_dir:
        id_list = args.id if args.id else get_dir_contents(args.rstar_dir)
        for dig_id in id_list:
            task["identifiers"] = [dig_id]
            publish(cursor, channel, task)
    else:
        publish(cursor, channel, task)

    mq_conn.close()
    db_conn.close()


if __name__ == "__main__":
    main()
