#!/usr/bin/python3

from tabulate import tabulate
import argparse
import json
import requests
import socket


def call_rabbitmq_api(host, port, user, passwd):
    url = f"http://{host}:{port}/api/queues/%2f/task_queue"
    try:
        r = requests.get(url, auth=(user, passwd))
    except requests.exceptions.RequestException as e:
        raise SystemExit(e)
    return r


def main():
    parser = argparse.ArgumentParser(description="Get connections")
    parser.add_argument("--host", default="localhost", help="Host")
    parser.add_argument("--port", type=int, default=15672, help="Port")
    parser.add_argument("--user", default="guest", help="User")
    parser.add_argument("--password", default="guest", help="Password")
    args = parser.parse_args()

    res = call_rabbitmq_api(args.host, args.port, args.user, args.password)
    qdata = res.json()

    # print("--- dump json ---")
    # print(json.dumps(qdata, indent=4))
    # print("--- get queue name ---")

    if qdata.get("consumer_details", []):
        headers = ["Host", "Port", "Queue"]
        connections = []
        # print("{:20}{:10}{:20}".format(*headers))
        # print("-" * 50)
        for consumer in qdata["consumer_details"]:
            host = consumer["channel_details"]["peer_host"]
            host = socket.gethostbyaddr(host)[0]
            port = consumer["channel_details"]["peer_port"]
            queue = consumer["queue"]["name"]
            connections.append([host, port, queue])
            # print(f"{host:20}{port!s:10}{queue:20}")

        print(tabulate(connections, headers=headers, tablefmt="pretty"))

if __name__ == "__main__":
    main()
