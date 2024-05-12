from configparser import ConfigParser
import os
import socket


def get_env() -> str:
    return "dev" if socket.gethostname().startswith("d") else "prod"


def get_rstar_dir() -> str:
    return os.path.join(os.sep, "content", get_env(), "rstar")


def get_sysconfig():
    env = get_env()
    etcdir = f"/content/{env}/rstar/etc"
    conf_file = f"{etcdir}/task-queue.sysconfig"

    config = {}
    if os.path.isfile(conf_file):
        with open(conf_file) as fh:
            for line in fh:
                line = line.partition("#")[0].strip()
                if line:
                    k, v = line.split("=")
                    config[k.lower()] = v
    return config


def get_myconfig():
    env = get_env()
    conf_file = f"/content/{env}/rstar/etc/my-taskqueue.cnf"
    config = ConfigParser()
    config.read(conf_file)
    return dict(config["client"])
