#!/usr/bin/python3

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


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Get connections")
    parser.add_argument("--host", default="localhost", help="Host")
    parser.add_argument("--port", type=int, default=15672, help="Port")
    parser.add_argument("--user", default="guest", help="User")
    parser.add_argument("--password", default="guest", help="Password")
    args = parser.parse_args()

    connections = set()

    res = call_rabbitmq_api(args.host, args.port, args.user, args.password)

    #   print("--- dump json ---")
    #   print(json.dumps(res.json(), indent=4))
    #   print("--- get queue name ---")

    qdata = res.json()

    if "consumer_details" in qdata:
        for consumer in qdata["consumer_details"]:
            peer_host = consumer["channel_details"]["peer_host"]
            connections.add(peer_host)

    for conn in connections:
        try:
            hostname = socket.gethostbyaddr(conn)[0]
        except socket.herror as e:
            hostname = conn
        print(hostname)

