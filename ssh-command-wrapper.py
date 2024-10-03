#!/usr/bin/python3

from pprint import pformat
import logging
import os
import shlex
import sys


def check_rsync():
    pass


def check_sbatch():
    pass


def main():
    level = logging.DEBUG
    homedir = os.path.expanduser("~")
    logfile = os.path.join(os.path.expanduser("~"), "logs", "ssh-command-log")
    logging.basicConfig(
        format="%(asctime)s %(levelname)s: %(message)s",
        level=level,
        datefmt="%m/%d/%Y %I:%M:%S %p",
        handlers=[logging.FileHandler(logfile)],
    )
    cmd_str = os.environ["SSH_ORIGINAL_COMMAND"]
    logging.debug(f"Original commmand: {cmd_str}")

    cmd_list = shlex.split(cmd_str)
    logging.debug("cmd: %s", pformat(cmd_list))

    sacct = os.path.join(homedir, "bin", "sacct.sh")
    logging.debug(f"sacct: {sacct}")
    if cmd_str == sacct:
        pass
    elif cmd_list[0] == "rsync":
        pass
    elif cmd_list[0] == "sbatch":
        pass
    else:
        sys.exit("Access denied")

    os.execvp(cmd_list[0], cmd_list)


if __name__ == "__main__":
    main()
