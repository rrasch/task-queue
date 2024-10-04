#!/usr/bin/python3

from pprint import pformat
import argparse
import logging
import os
import shlex
import sys


class ArgumentParsingError(Exception):
    pass


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ArgumentParsingError(message)


def check_rsync(cmd):
    expected = ["rsync", "--server", "--sender", "-vlogDtprze.iLsfxC", "."]
    if len(cmd) != len(expected) + 1:
        return False
    if cmd[:-1] != expected:
        logging.error(f"{cmd[:-1]} != {expected}")
        return False
    if not os.path.isdir(cmd[-1]):
        logging.error(f"Last arg '{cmd[-1]}' is not a directory.")
        return False
    return True


def get_args(parser):
    return [
        action.option_strings if action.option_strings else [action.dest]
        for action in parser._actions
    ]


def check_sbatch(cmd):
    if cmd[0] != "sbatch":
        logging.debug(f"{cmd[0]} != sbatch")
        return False

    parser = ArgumentParser(add_help=False)
    parser.add_argument("--output", required=True)
    parser.add_argument("--mem", required=True)
    parser.add_argument("--time", required=True)
    parser.add_argument("--mail-user", required=True)
    parser.add_argument("script")
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("job_id")

    args_list = get_args(parser)
    logging.debug("arg list: %s", pformat(args_list))

    num_args = len(args_list)
    logging.debug(f"num args: {num_args}")

    main_args = cmd[1:num_args]
    try:
        args = parser.parse_args(main_args)
        logging.debug(f"args: {args}")
    except ArgumentParsingError:
        logging.exception(f"Can't parse args {main_args}")
        return False

    profile_args = cmd[num_args:]
    parser = ArgumentParser(add_help=False)
    parser.add_argument("--profiles_path", action="append")
    try:
        args = parser.parse_args(profile_args)
        logging.debug(f"args: {args}")
    except ArgumentParsingError:
        logging.exception(f"Can't parse args {profile_args}")
        return False

    return True


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
    elif check_rsync(cmd_list):
        pass
    elif check_sbatch(cmd_list):
        pass
    else:
        logging.error("Access denied")
        sys.exit("Access denied")

    os.execvp(cmd_list[0], cmd_list)


if __name__ == "__main__":
    main()
