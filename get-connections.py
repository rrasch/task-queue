#!/usr/bin/python3

from pprint import pformat, pprint
import argparse
import json
import logging
import os
import requests
import socket
import tqcommon


def call_rabbitmq_api(host, port, user, passwd, qname):
    url = f"http://{host}:{port}/api/queues/%2f/{qname}"
    try:
        r = requests.get(url, auth=(user, passwd))
    except requests.exceptions.RequestException as e:
        raise SystemExit(e)
    return r


def reverse_lookup(addr):
    try:
        return socket.gethostbyaddr(addr)[0]
    except socket.herror:
        return addr


def main():
    config = tqcommon.get_sysconfig()
    aliases = tqcommon.get_host_aliases()

    parser = argparse.ArgumentParser(
        description="List connections by querying RabbitMQ API"
    )
    parser.add_argument(
        "--host",
        default=config.get("mqhost", "localhost"),
        help="Host (default: %(default)s)",
    )
    parser.add_argument(
        "--port", type=int, default=15672, help="Port (default: %(default)s)"
    )
    parser.add_argument("--user", default="guest", help="User")
    parser.add_argument("--password", default="guest", help="Password")
    parser.add_argument(
        "--queue",
        default="task_queue",
        help="Queue name (default: %(default)s)",
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debugging"
    )
    args = parser.parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(format="%(levelname)s: %(message)s", level=level)

    logging.debug("config=%s", pformat(config))
    logging.debug("aliases=%s", pformat(aliases))

    try:
        from tabulate import tabulate
        tab_loaded = True
    except ImportError as e:
        logging.warning("Can't load tabulate module")
        tab_loaded = False

    res = call_rabbitmq_api(
        args.host, args.port, args.user, args.password, args.queue
    )
    qdata = res.json()

    logging.debug("--- dump json ---")
    logging.debug(json.dumps(qdata, indent=4))

    if qdata.get("consumer_details", []):
        headers = ["Host", "Port", "Queue"]
        connections = []
        for consumer in qdata["consumer_details"]:
            host = consumer["channel_details"]["peer_host"]
            host = reverse_lookup(host)
            host = aliases.get(host, host)
            port = consumer["channel_details"]["peer_port"]
            queue = consumer["queue"]["name"]
            connections.append([host, port, queue])

        connections.sort(key=lambda x: (x[0], x[1]))

        if tab_loaded:
            print(tabulate(connections, headers=headers, tablefmt="pretty"))
        else:
            if connections:
                print("{:40}{:10}{:20}".format(*headers))
                print("-" * 70)
                for host, port, queue in connections:
                    print(f"{host:40}{port!s:10}{queue:20}")


if __name__ == "__main__":
    main()
