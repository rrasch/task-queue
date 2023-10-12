import socket


def get_env() -> str:
    return "dev" if socket.gethostname().startswith("d") else "prod"
