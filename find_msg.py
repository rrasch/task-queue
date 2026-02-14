#!/usr/bin/python3

import argparse
import pika
import tqcommon


def main():
    sysconfig = tqcommon.get_sysconfig()

    parser = argparse.ArgumentParser(
        description=(
            "Search a RabbitMQ queue for a message containing PATTERN.\n"
            "Default is read-only. Use --delete to ACK and remove the message."
        )
    )
    parser.add_argument(
        "pattern", help="Substring or regex to match in message body"
    )
    parser.add_argument(
        "--queue",
        default="task_queue",
        help="Queue name (default: %(default)s)",
    )
    parser.add_argument(
        "--host",
        default=sysconfig.get("mqhost", "localhost"),
        help="RabbitMQ host (default: %(default)s)",
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="ACK and remove the matching message (DANGEROUS)",
    )
    args = parser.parse_args()

    connection = pika.BlockingConnection(pika.ConnectionParameters(args.host))
    channel = connection.channel()
    channel.queue_declare(
        queue=args.queue, durable=True, arguments={"x-max-priority": 10}
    )

    print(f"Scanning queue={args.queue} for pattern={args.pattern!r}")

    while True:
        method, props, body = channel.basic_get(args.queue, auto_ack=False)

        if method is None:
            print("Queue is empty.")
            break

        msg = body.decode(errors="replace")

        if args.pattern in msg:
            print("FOUND MATCH:")
            print(msg)
            if args.delete:
                channel.basic_ack(method.delivery_tag)
                print("Message ACKed (removed from queue)")
            else:
                channel.basic_nack(method.delivery_tag, requeue=True)
                print("Read-only mode: message left in queue")
            break
        else:
            # Put it back
            channel.basic_nack(method.delivery_tag, requeue=True)

    connection.close()


if __name__ == "__main__":
    main()
