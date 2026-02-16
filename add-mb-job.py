#!/usr/bin/python3

from pprint import pformat
import MySQLdb
import argparse
import json
import logging
import os
import pika
import psutil
import sys
import tqcommon
import util


QUEUE_NAME = "task_queue"
EXCHANGE_NAME = "tq_logging"
CHANNEL_MAX = 32
PERSISTENT_DELIVERY_MODE = 2

PATH_ARGS = ("rstar_dir", "input_path", "output_path")


def usage(parser, msg, brief=True):
    print(msg, file=sys.stderr)
    if brief:
        parser.print_usage(sys.stderr)
    else:
        parser.print_help(sys.stderr)
    sys.exit(1)


def do_query(cursor, query, values):
    num_rows = cursor.execute(query, values)
    logging.debug("rows affected: %s", num_rows)
    if num_rows == 0:
        filled_query = " ".join((query % values).split())
        logging.warning("No rows affected for query: %s", filled_query)


def publish(cursor, channel, task):
    body = json.dumps(task, indent=4)
    query = """
        INSERT INTO job
        (batch_id, request, user_id, state, submitted)
        VALUES (%s, %s, %s, 'pending', NOW())
    """
    do_query(cursor, query, (task["batch_id"], body, task["user_id"]))

    task["job_id"] = cursor.lastrowid
    logging.debug("job id: %s", task["job_id"])
    body = json.dumps(task, indent=4)
    task.pop("job_id")
    logging.debug("Sending body:\n%s", pformat(task))

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
    filepath = os.path.realpath(filepath)
    if not os.path.exists(filepath):
        raise argparse.ArgumentTypeError(f"File not found: '{filepath}'")
    return filepath


def get_nfs_mounts():
    return [
        part.mountpoint
        for part in psutil.disk_partitions(all=True)
        if part.fstype.startswith("nfs")
    ]


def check_paths_on_nfs(args_dict):
    """Ensure path arguments are on NFS mount if NFS mounts exist."""
    nfs_mounts = get_nfs_mounts()
    if not nfs_mounts:
        return

    for arg_name in PATH_ARGS:
        filepath = args_dict.get(arg_name)
        if filepath and not any(
            filepath.startswith(mount) for mount in nfs_mounts
        ):
            sys.exit(f"ERROR: {filepath} must be on an NFS mount")


def rewrite_extra_args(argv):
    new_argv = []
    i = 0
    while i < len(argv):
        if argv[i] in ("-e", "--extra-args") and i + 1 < len(argv):
            new_argv.append(f"{argv[i]}={argv[i+1]}")
            i += 2
        else:
            new_argv.append(argv[i])
            i += 1
    return new_argv


def main():
    my_conf_file = tqcommon.get_myconfig_file()
    sysconfig = tqcommon.get_sysconfig()
    services = tqcommon.get_services()

    orig_argv = sys.argv
    sys.argv = rewrite_extra_args(sys.argv)

    parser = argparse.ArgumentParser(allow_abbrev=False)
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
    parser.add_argument(
        "-s",
        "--service",
        choices=services,
        help="service, e.g. video:transcode",
    )
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

    logging.debug("orig argv: %s", orig_argv)
    logging.debug("sys.argv: %s", sys.argv)

    args_dict = vars(args)
    logging.debug("args dict:\n%s", pformat(args_dict))

    logging.debug("sysconfig: %s", pformat(sysconfig))

    cmd_line = util.shlex_join([os.path.realpath(sys.argv[0]), *sys.argv[1:]])
    logging.debug(f"cmd line: {cmd_line}")

    if args.test:
        print("Running in test mode.")

    if not args.test:
        if not args.service:
            usage(parser, "You must set -s to define the service.")

        cls, delim, op = args.service.partition(":")

        if not cls or not op:
            parser.error(
                "You must set -s to define service in the format "
                "<class>:<service>,  e.g. audio:transcode",
            )

        if cls != "util":
            has_rstar = bool(args.rstar_dir)
            has_input = bool(args.input_path)
            has_output = bool(args.output_path)
            has_both_io_paths = has_input and has_output

            # Require rstar_dir or input/output paths to be set
            if not has_rstar and not has_both_io_paths:
                parser.error("Missing rstar_dir or input/output path pair")

            # rstar_dir is mutually exclusive with input/output
            if has_rstar and (has_input or has_output):
                parser.error("rstar_dir can't be used with input/output paths")

            # input/output must be paired
            if has_input ^ has_output:
                parser.error("input/output paths must be set together")

            check_paths_on_nfs(args_dict)

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
        mq_conn.close()
        db_conn.close()
        sys.exit(0)

    login = os.getlogin()

    query = "INSERT into batch (user_id, cmd_line) VALUES (%s, %s)"
    do_query(cursor, query, (login, cmd_line))
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

    for arg_name in PATH_ARGS:
        if args_dict[arg_name]:
            task[arg_name] = args_dict[arg_name]

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
