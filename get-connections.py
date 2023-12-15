#!/usr/bin/python3

from pprint import pformat
import argparse
import json
import logging
import os
import requests
import socket
import tqcommon


def call_rabbitmq_api(host, port, user, passwd):
    url = f"http://{host}:{port}/api/queues/%2f/task_queue"
    try:
        r = requests.get(url, auth=(user, passwd))
    except requests.exceptions.RequestException as e:
        raise SystemExit(e)
    return r


def main():
    env = tqcommon.get_env()
    conf_file = f"/content/{env}/rstar/etc/task-queue.sysconfig"

    config = {}
    if os.path.isfile(conf_file):
        with open(conf_file) as fh:
            for line in fh:
                line = line.partition("#")[0].strip()
                if line:
                    k, v = line.split("=")
                    config[k] = v

    parser = argparse.ArgumentParser(description="Get connections")
    parser.add_argument(
        "--host", default=config.get("MQHOST", "localhost"), help="Host"
    )
    parser.add_argument("--port", type=int, default=15672, help="Port")
    parser.add_argument("--user", default="guest", help="User")
    parser.add_argument("--password", default="guest", help="Password")
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debugging"
    )
    args = parser.parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(format="%(levelname)s: %(message)s", level=level)

    logging.debug("config=%s", pformat(config))

    try:
        from tabulate import tabulate
        tab_loaded = True
    except ImportError as e:
        logging.warning("Can't load tabulate module")
        tab_loaded = False

    res = call_rabbitmq_api(args.host, args.port, args.user, args.password)
    qdata = res.json()

    logging.debug("--- dump json ---")
    logging.debug(json.dumps(qdata, indent=4))
    logging.debug("--- get queue name ---")

    if qdata.get("consumer_details", []):
        headers = ["Host", "Port", "Queue"]
        connections = []
        if not tab_loaded:
            print("{:20}{:10}{:20}".format(*headers))
            print("-" * 50)
        for consumer in qdata["consumer_details"]:
            host = consumer["channel_details"]["peer_host"]
            host = socket.gethostbyaddr(host)[0]
            port = consumer["channel_details"]["peer_port"]
            queue = consumer["queue"]["name"]
            connections.append([host, port, queue])
            if not tab_loaded:
                print(f"{host:20}{port!s:10}{queue:20}")

        if tab_loaded:
            print(tabulate(connections, headers=headers, tablefmt="pretty"))


if __name__ == "__main__":
    main()
