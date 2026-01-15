from argparse import ArgumentTypeError
from datetime import datetime
import logging
import time
import shlex
import subprocess


def quote(val):
    if type(val) is str:
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


def shlex_join(split_command):
    """Return a shell-escaped string from *split_command*."""
    return " ".join(shlex.quote(arg) for arg in split_command)


def is_pos_int(val):
    try:
        int_val = int(val)
    except ValueError:
        int_val = None
    if int_val is None or int_val < 1:
        raise ArgumentTypeError(f"'{val}' is not a positive integer")
    return int_val


def get_boot_time():
    """
    Return the system boot time as a timezone-aware datetime object.
    Uses `uptime -s`, which prints timestamps in the system's locale.
    """
    # Run uptime -s and capture stdout
    result = subprocess.run(
        ["uptime", "-s"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        encoding="utf-8",
        check=True,
    )

    boot_str = result.stdout.strip()  # e.g. "2025-12-03 16:37:06"

    # Parse into a datetime object
    # uptime -s always uses "%Y-%m-%d %H:%M:%S"
    boot_dt = datetime.strptime(boot_str, "%Y-%m-%d %H:%M:%S")

    # Make it timezone-aware using the system's local timezone
    boot_dt = boot_dt.astimezone()

    return boot_dt
