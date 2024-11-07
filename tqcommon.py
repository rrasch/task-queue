from configparser import ConfigParser
import os
import socket
import tomli
import yaml


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


def get_myconfig_file():
    return f"/content/{get_env()}/rstar/etc/my-taskqueue.cnf"


def get_myconfig():
    conf_file = get_myconfig_file()
    config = ConfigParser()
    config.read(conf_file)
    return dict(config["client"])


def get_hpc_config():
    conf_file = os.path.join(get_rstar_dir(), "etc", "hpc-taskqueue.toml")
    with open(conf_file, "rb") as f:
        config = tomli.load(f)
    return config["main"]


def get_host_aliases():
    alias_file = f"/content/{get_env()}/rstar/etc/host-aliases.yaml"
    aliases = {}
    if os.path.exists(alias_file):
        with open(alias_file) as fh:
            aliases = yaml.safe_load(fh)["aliases"]
    return aliases
