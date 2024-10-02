#!/usr/bin/env python3

from concurrent.futures import ThreadPoolExecutor
from systemd import journal
import argparse
import os
import socket
import subprocess as sp
import time
import tqcommon
import sys


def test_port(host, port, retries=5, delay=2):
    """Tests if a port is open.

    Args:
        ip:      The IP address of the host to test.
        port:    The port number to test.
        retries: The number of times to retry the test.
        delay:   The delay in seconds between retries.

    Returns:
        True if the port is open, False otherwise.
    """
    for i in range(retries):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.connect((host, int(port)))
            return True
        except socket.error:
            time.sleep(delay)
        finally:
            sock.close()

    return False


def get_uptime():
    """Get uptime in minutes."""
    with open("/proc/uptime") as f:
        uptime_seconds = float(f.readline().split()[0])

    return uptime_seconds / 60


def log(msg):
    """Write to systemd journal.

    Args:
        msg: String message sent to journal
    """
    journal.send(msg, SYSLOG_IDENTIFIER="task-queue")


def can_list_files(mountpoint, timeout=5):
    try:
        sp.run(
            ["ls", mountpoint],
            stdout=sp.PIPE,
            stderr=sp.STDOUT,
            universal_newlines=True,
            timeout=timeout,
        )
    except (sp.CalledProcessError, sp.TimeoutExpired) as e:
        return False
    else:
        return True


def is_nfs_mount(mount_point):
    with open("/proc/mounts", "r") as f:
        mounts = f.readlines()
        for mount in mounts:
            if mount_point in mount and "nfs" in mount:
                return True
    return False


def check_nfs_mount(mount_point):
    if not os.path.ismount(mount_point):
        return False
    if not is_nfs_mount(mount_point):
        return False
    if not can_list_files(mount_point):
        return False
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Test ports required by task queue"
    )
    parser.add_argument(
        "--mysql", action="store_true", help="Test connection to mysql"
    )
    parser.add_argument(
        "--smtp", action="store_true", help="Test connection to mail server"
    )
    args = parser.parse_args()

    uptime = get_uptime()
    if uptime < 1:
        time.sleep(15)

    sysconfig = tqcommon.get_sysconfig()
    sock_addrs = [(sysconfig["mqhost"], socket.getservbyname("amqp"))]

    if args.mysql:
        myconfig = tqcommon.get_myconfig()
        sock_addrs.append((myconfig["host"], socket.getservbyname("mysql")))

    if args.smtp:
        sock_addrs.append(("localhost", socket.getservbyname("smtp")))

    with ThreadPoolExecutor() as executor:
        futures = {
            executor.submit(test_port, host, port): f"{host}:{port}"
            for host, port in sock_addrs
        }

    success = True
    for future in futures:
        is_port_open = future.result()
        status = "open" if is_port_open else "closed"
        success = success and is_port_open
        log(f"Port {futures[future]} is {status}")

    if success:
        status = "succeeded"
        exit_val = 0
    else:
        status = "failed"
        exit_val = 1

    log(f"Testing for required ports {status}")
    sys.exit(exit_val)


if __name__ == "__main__":
    main()
