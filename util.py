from argparse import ArgumentTypeError
import logging
import time
import shlex


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
