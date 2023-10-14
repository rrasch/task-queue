import os
import socket


def get_env() -> str:
    return "dev" if socket.gethostname().startswith("d") else "prod"


def get_rstar_dir() -> str:
    return os.path.join(os.sep, "content", get_env(), "rstar")
