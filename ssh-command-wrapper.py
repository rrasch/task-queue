#!/usr/bin/python3

from pprint import pformat
import argparse
import filetype
import logging
import os
import shlex
import sys
import time
import xml.etree.ElementTree as ET


class ArgumentParsingError(Exception):
    pass


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ArgumentParsingError(message)


def quote(val):
    if type(val) == str:
        return f"'{val}'"
    else:
        return str(val)


def create_args_str(*args, **kwargs):
    sep = ", "
    arg_str = sep.join([quote(a) for a in args])
    kw_str = sep.join([f"{k}={quote(kwargs[k])}" for k in kwargs.keys()])

    if arg_str and kw_str:
        return arg_str + sep + kw_str
    elif arg_str:
        return arg_str
    else:
        return kw_str


def logfunc(func):
    def wrapper(*args, **kwargs):
        arg_str = create_args_str(*args, **kwargs)
        logging.debug(f"{time.ctime()}  entering {func.__name__}({arg_str})")
        retvals = func(*args, **kwargs)
        logging.debug(f"{time.ctime()}  {func.__name__} returned: {retvals}")
        return retvals

    return wrapper


@logfunc
def check_rsync(cmd, check_sender=False):
    expected = ["rsync", "--server", "-svlogDtprRze.iLsfxC"]
    if cmd != expected:
        logging.error(f"{cmd} != {expected}")
        return False
    return True


@logfunc
def check_rsync_sender(cmd):
    expected = ["rsync", "--server", "--sender", "-vlogDtprze.iLsfxC", "."]
    if len(cmd) != len(expected) + 1:
        logging.error(f"{len(cmd)} != {len(expected) + 1}")
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


@logfunc
def is_xml(file_path):
    try:
        ET.parse(file_path)
        return True
    except ET.ParseError:
        return False


@logfunc
def is_video(file_path):
    kind = filetype.guess(file_path)
    if kind is None:
        return False
    return kind.mime.startswith("video/")


@logfunc
def check_sbatch(cmd):
    if cmd[0] != "sbatch":
        logging.debug(f"{cmd[0]} != sbatch")
        return False

    cmd_args = cmd[1:]

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

    main_args = cmd_args[:num_args]
    try:
        parsed_args = parser.parse_args(main_args)
        logging.debug(f"parsed args: {parsed_args}")
    except ArgumentParsingError:
        logging.exception(f"Can't parse args {main_args}")
        return False

    script_file = os.path.join(
        os.path.expanduser("~"), "work", "hpc-transcode", "submit-one.sh"
    )
    if parsed_args.script != script_file:
        logging.error(f"{parsed_args.script} != {script_file}")
        return False

    if not is_video(parsed_args.input):
        logging.error(f"{parsed_args.input} is not a video file")
        return False

    if not parsed_args.output.startswith(os.environ["SCRATCH"]):
        logging.error(
            f"Output base '{parsed_args.output}' does not start with"
            f" '{os.environ['SCRATCH']}'"
        )
        return False

    if not parsed_args.job_id.isdigit():
        logging.error(f"{parsed_args.job_id} is not an integer")
        return False

    profile_args = cmd_args[num_args:]
    parser = ArgumentParser(add_help=False)
    parser.add_argument("--profiles_path", action="append")
    try:
        parsed_args = parser.parse_args(profile_args)
        logging.debug(f"parsed args: {parsed_args}")
    except ArgumentParsingError:
        logging.exception(f"Can't parse args {profile_args}")
        return False

    for profile in parsed_args.profiles_path or []:
        if not is_xml(profile):
            logging.error(f"{profile} is no a valid XML file.")
            return False

    return True


def check_sacct(cmd):
    sacct_paths = [
        os.path.join(d, "bin", "sacct.sh")
        for d in ("~", os.path.expanduser("~"))
    ]
    logging.debug(f"sacct paths: {sacct_paths}")
    if cmd not in sacct_paths:
        logging.error(f"{cmd} not in {sacct_paths}")
        return False
    return True


def main():
    level = logging.DEBUG
    logfile = os.path.join(os.path.expanduser("~"), "logs", "ssh-command-log")
    logging.basicConfig(
        format="%(asctime)s %(levelname)s: %(message)s",
        level=level,
        datefmt="%m/%d/%Y %I:%M:%S %p",
        handlers=[logging.FileHandler(logfile)],
    )

    logging.debug("env: %s:", pformat(dict(os.environ)))

    os.environ.pop("DISPLAY", "")
    os.environ.pop("XDG_SESSION_COOKIE", "")
    os.environ.pop("XAUTHORITY", "")

    cmd_str = os.environ["SSH_ORIGINAL_COMMAND"]
    logging.debug(f"Original commmand: {cmd_str}")

    cmd_list = shlex.split(cmd_str)
    logging.debug("cmd: %s", pformat(cmd_list))

    if check_sacct(cmd_str):
        pass
    elif check_rsync(cmd_list):
        pass
    elif check_rsync_sender(cmd_list):
        pass
    elif check_sbatch(cmd_list):
        pass
    else:
        logging.error("Access denied")
        sys.exit("Access denied")

    os.execvp(cmd_list[0], cmd_list)


if __name__ == "__main__":
    main()