#!/usr/bin/python3

from collections import Counter
from pprint import pformat
from typing import Optional
import MySQLdb
import argparse
import json
import logging
import os
import pika
import psutil
import re
import requests
import sys
import tqcommon
import util


QUEUE_NAME = "task_queue"
EXCHANGE_NAME = "tq_logging"
CHANNEL_MAX = 32
PERSISTENT_DELIVERY_MODE = 2

PATH_ARGS = ("rstar_dir", "input_path", "output_path")

IDENT_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


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


def validate_identifier(value):
    if not IDENT_RE.match(value):
        raise argparse.ArgumentTypeError(
            f"invalid identifier '{value}': must match {IDENT_RE.pattern}"
        )
    return value


def validate_filepath(filepath):
    """Validates a filepath and returns it if valid."""
    filepath = os.path.realpath(filepath)
    if not os.path.exists(filepath):
        raise argparse.ArgumentTypeError(f"File not found: '{filepath}'")
    return filepath


def validate_parent_path(filepath):
    """
    Argparse type function: checks that the parent directory of filepath exists.
    """
    filepath = os.path.realpath(filepath)
    parent = os.path.dirname(filepath) or "."

    if not os.path.isdir(parent):
        raise argparse.ArgumentTypeError(
            f"Parent directory does not exist: '{parent}'"
        )

    return filepath


def parse_service(service, parser):
    """
    Parse and validate a service string in "<class>:<service>" format.

    Splits the provided service string into its class and operation
    components using ":" as a delimiter. Ensures that both components
    are present and non-empty.

    Args:
        service: String specifying the service in "<class>:<service>"
            format (e.g. "audio:transcode").
        parser: ArgumentParser instance used to report errors.

    Returns:
        A tuple (cls, op) where ``cls`` is the service class and ``op``
        is the service operation.

    Raises:
        SystemExit: If the service is missing or not in the expected
            format. Triggered via ``usage()`` or ``parser.error()``.
    """
    if not service:
        usage(parser, "You must set -s to define the service.")

    cls, delim, op = service.partition(":")

    if not cls or not op:
        parser.error(
            "You must set -s to define service in the format "
            "<class>:<service>, e.g. audio:transcode",
        )

    return cls, op


def validate_io_paths(args, parser):
    """
    Validate combinations of I/0 path-related command-line arguments.

    Ensures that either ``rstar_dir`` is provided, or both
    ``input_path`` and ``output_path`` are provided together. Enforces
    that ``rstar_dir`` is mutually exclusive with ``input_path`` and
    ``output_path``, and that input/output paths are specified as a
    pair. Also performs additional checks on the provided paths (e.g.,
    verifying constraints such as NFS usage).

    Args:
        args: Parsed argparse namespace containing ``rstar_dir``,
            ``input_path``, and ``output_path`` attributes.
        parser: ArgumentParser instance used to report errors.

    Raises:
        SystemExit: If validation fails. Triggered via
            ``parser.error()``, which prints an error message and
            exits the program, or by helper validation functions.
    """
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

    # Make sure any path given is on isilon filesystem
    check_paths_on_nfs(vars(args))


def validate_transcode_output_path(input_path, output_path):
    """
    Validates output_path based on input_path type:

    - If input_path is a file:
        - output_path is treated as a file prefix
        - parent directory must exist
        - output_path must not be a directory
    - If input_path is a directory:
        - output_path must be an existing directory
    """
    output_path = os.path.realpath(output_path)

    # Input is a file so must output be a prefix
    if os.path.isfile(input_path):
        parent = os.path.dirname(output_path) or "."

        if not os.path.isdir(parent):
            raise ValueError(
                f"Output prefix directory does not exist: '{parent}'"
            )

        if os.path.isdir(output_path):
            raise ValueError(
                "Output path must be a file prefix, not a directory:"
                f" '{output_path}'"
            )

        return output_path

    # Input is a directory so output must also be a directory
    elif os.path.isdir(input_path):
        if not os.path.isdir(output_path):
            raise ValueError(
                "When input is a directory, output must also be a directory:"
                f" '{output_path}'"
            )

        return output_path

    else:
        # Should not happen if argparse validated input_path
        raise RuntimeError(f"Unexpected input path type: '{input_path}'")


def validate_operation(args, op):
    """
    Apply operation-specific validation and safeguards.

    Enforces additional constraints and confirmations that depend on the
    selected operation. These checks go beyond general argument validation
    and reflect behavior or safety requirements for particular operations.

    For example:
    - ``transcode`` may impose additional rules on input/output paths.
    - ``convert_iso`` may require user confirmation when running with
      multiple workers.

    Args:
        args: Parsed argparse namespace containing relevant attributes
            such as ``input_path``, ``output_path``, and ``mqhost``.
        op: The operation name extracted from the service string.

    Raises:
        SystemExit: If a validation or confirmation step fails. Triggered
            by called helper functions that report errors or prompt exit.
    """
    if op == "transcode" and args.input_path:
        validate_transcode_output_path(args.input_path, args.output_path)

    if op == "convert_iso" and is_multiple_workers(args.mqhost):
        confirm_handbrake_job()


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


def log_warn(msg, e):
    logging.warning("%s - %s %s", msg, type(e).__name__, e)


def get_consumer_counts(mqhost: str) -> Optional[Counter]:
    """
    Retrieve and count RabbitMQ queue consumers by peer host.

    This function queries the RabbitMQ management API for the
    "task_queue" queue on the specified host, extracts the consumer
    details, and returns a Counter mapping each peer_host to the
    number of consumers connected from that host.

    If the API request fails or the expected data is missing, a
    warning is logged and None is returned.

    Parameters:
        mqhost (str): Hostname or IP address of the RabbitMQ server.

    Returns:
        collections.Counter or None: A Counter where keys are
        peer_host values and values are the number of consumers
        from each host, or None if an error occurs.
    """
    api_url = f"http://{mqhost}:15672/api/queues/%2f/task_queue"
    try:
        response = requests.get(api_url, timeout=2, auth=("guest", "guest"))
        queue_data = response.json()
        consumer_details = queue_data["consumer_details"]
    except requests.exceptions.RequestException as e:
        log_warn("Problem calling management API", e)
        return
    except KeyError as e:
        log_warn("Consumer details not found in queue data", e)
        return

    return Counter(
        consumer["channel_details"]["peer_host"]
        for consumer in consumer_details
    )


def is_multiple_workers(mqhost):
    worker_counts = get_consumer_counts(mqhost)
    logging.debug("Consumers: %s", pformat(worker_counts))
    if worker_counts:
        return any(count > 1 for count in worker_counts.values())
    else:
        return False


def confirm_handbrake_job():
    warning = """
WARNING: The task-queue currently has multiple workers per host.
Running HandBrake in parallel with other jobs may overload the server.
Do you want to still send this job?
Type 'yes' to confirm, anything else will cancel.
"""
    print(warning)
    response = input("> ").strip().lower()
    if response != "yes":
        print("Job cancelled to avoid server overload.")
        sys.exit(0)


def merge_dicts(cli, json_cfg):
    conflicts = [k for k in json_cfg.keys() if cli.get(k) is not None]

    if conflicts:
        raise ValueError(
            "Configuration conflict: the following keys were provided via CLI "
            "and also exist in the JSON configuration: "
            f"{sorted(conflicts)}"
        )

    return {**cli, **json_cfg}


def load_json_config(filepath):
    with open(filepath) as f:
        return json.load(f)


def json_to_argv(data):
    pos_list = []
    args_list = []

    for k, v in data.items():
        if k == "identifiers":
            pos_list.extend(v)
        else:
            args_list.append(f"--{k.replace('_', '-')}")
            args_list.append(v)

    args_list.extend(pos_list)
    return rewrite_extra_args(args_list)


def merge_json_with_cli(cli_args, parser):
    """
    Merge CLI arguments with a JSON configuration file using argparse
    validation.

    This function loads a JSON configuration file and converts it into a
    synthetic argv list. The JSON-derived arguments are parsed through the
    provided argparse parser to reuse argparse validation rules (types,
    choices, actions, etc.).

    The final configuration is produced by merging:
        - CLI arguments (base configuration)
        - JSON-derived values (applied on top of CLI)

    CLI and JSON must not define the same configuration keys.
    Overlapping keys are treated as invalid and raise an error.

    Processing steps:
        1. Load JSON configuration from cli_args.json_config
        2. Convert JSON configuration into a synthetic argv list
        3. Parse JSON argv through argparse for validation
        4. Merge JSON values into CLI arguments
        5. Return argparse.Namespace with final values

    Parameters
    ----------
    cli_args : argparse.Namespace
        Parsed CLI arguments, including json_config file path.
    parser : argparse.ArgumentParser
        Parser used to validate JSON-derived arguments.

    Returns
    -------
    argparse.Namespace
        Final configuration with JSON values merged into CLI arguments.

    Notes
    -----
    JSON is validated by simulating CLI argument parsing. CLI remains the
    base configuration, and JSON is applied as an overlay. Conflicts are
    treated as invalid state and raise an exception.
    """
    json_config = load_json_config(cli_args.json_config)
    logging.debug("json config: %s", pformat(json_config))

    json_argv = json_to_argv(json_config)
    logging.debug("json argv: %s", json_argv)

    json_args = parser.parse_args(json_argv)
    logging.debug("json args: %s", json_args)

    final_config = merge_dicts(vars(cli_args), json_config)
    logging.debug("final merged config: %s", pformat(final_config))

    return argparse.Namespace(**final_config)


def main():
    my_conf_file = tqcommon.get_myconfig_file()
    sysconfig = tqcommon.get_sysconfig()
    services = tqcommon.get_services()

    orig_argv = sys.argv
    sys.argv = rewrite_extra_args(sys.argv)

    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument(
        "identifiers",
        metavar="ID",
        nargs="*",
        type=validate_identifier,
        default=None,
        help="Digital object identifier",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose messages",
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
    parser.add_argument(
        "-r",
        "--rstar-dir",
        type=validate_filepath,
        help="R* (Rstar) directory",
    )
    parser.add_argument(
        "-i",
        "--input-path",
        type=validate_filepath,
        help="input path (directory or file)",
    )
    parser.add_argument(
        "-o",
        "--output-path",
        type=validate_parent_path,
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
        type=int,
        choices=range(11),
        help="message priority (default: 0, lowest priority)",
    )
    parser.add_argument(
        "-s",
        "--service",
        choices=services,
        help="service, e.g. video:transcode",
    )
    parser.add_argument(
        "-e",
        "--extra-args",
        help="extra command line args",
    )
    parser.add_argument(
        "-j",
        "--json-config",
        type=validate_filepath,
        help="json config to pass to job",
    )
    args = parser.parse_args()

    if not args.identifiers:
        args.identifiers = None

    level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        format="%(asctime)s %(levelname)s: %(message)s",
        level=level,
        datefmt="%m/%d/%Y %I:%M:%S %p",
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    logging.debug("orig argv: %s", orig_argv)
    logging.debug("sys.argv: %s", sys.argv)

    logging.debug("sysconfig: %s", pformat(sysconfig))

    cmd_line = util.shlex_join([os.path.realpath(sys.argv[0]), *sys.argv[1:]])
    logging.debug(f"cmd line: {cmd_line}")

    if args.json_config:
        args = merge_json_with_cli(args, parser)
        logging.debug("New args: %s", args)

    args_dict = vars(args)
    logging.debug("args dict:\n%s", pformat(args_dict))

    if not args.test:
        cls, op = parse_service(args.service, parser)
        if cls != "util":
            validate_io_paths(args, parser)
            validate_operation(args, op)

    mq_conn = None
    db_conn = None

    try:
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
            "server capabilities: %s",
            pformat(mq_conn._impl.server_capabilities),
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

        db_conn = MySQLdb.connect(
            read_default_file=my_conf_file, autocommit=True
        )
        cursor = db_conn.cursor()

        if args.test:
            print("Test succeeded.")
            sys.exit(0)

        login = os.getlogin()

        query = "INSERT into batch (user_id, cmd_line) VALUES (%s, %s)"
        do_query(cursor, query, (login, cmd_line))
        batch_id = cursor.lastrowid

        task = {
            "class": cls,
            "operation": op,
            "extra_args": args.extra_args or "",
            "user_id": os.getlogin(),
            "batch_id": batch_id,
            "state": "pending",
            "priority": args.priority or 0,
        }

        for arg_name in PATH_ARGS:
            if args_dict[arg_name]:
                task[arg_name] = args_dict[arg_name]

        logging.debug("task:\n%s", pformat(task))

        if args.rstar_dir:
            id_list = (
                args.identifiers
                if args.identifiers
                else get_dir_contents(args.rstar_dir)
            )
            for dig_id in id_list:
                task["identifiers"] = [dig_id]
                publish(cursor, channel, task)
        else:
            publish(cursor, channel, task)

        print(f"The batch id {batch_id}")

    finally:
        if mq_conn:
            mq_conn.close()
        if db_conn:
            db_conn.close()


if __name__ == "__main__":
    main()
