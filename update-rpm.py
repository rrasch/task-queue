#!/usr/bin/env python3

import functools
import glob
import logging
import os
import socket
import subprocess
import sys
import tempfile

import pika
import rpm

import tqcommon
from util import shlex_join

logger = logging.getLogger(__name__)


def get_redhat_version():
    with open("/etc/os-release", "r") as fh:
        for line in fh:
            if line.startswith("VERSION_ID="):
                return line.split("=")[1].strip().strip('"').split(".")[0]
    return None


def readRpmHeader(ts, filename):
    """Read an rpm header."""
    fd = os.open(filename, os.O_RDONLY)
    try:
        h = ts.hdrFromFdno(fd)
    finally:
        os.close(fd)
    return h


def _is_newer(version1, version2):
    logger.debug(f"comparing {version1} to {version2}")
    return version1 > version2


def is_newer(version1, version2):
    logger.debug(f"comparing {version1} to {version2}")
    rc = rpm.labelCompare(version1, version2)
    logger.debug(f"rc={rc}")
    return rc > 0


def _can_update(rpm_file):
    trans_set = rpm.TransactionSet()
    local_header = readRpmHeader(trans_set, rpm_file)
    local_dep_set = local_header.dsOfHeader()
    name = local_header["name"]
    installed_dep_sets = [
        hdr.dsOfHeader() for hdr in trans_set.dbMatch("name", name)
    ]
    if not installed_dep_sets:
        logger.info(f"{name} is not installed, OK to update.")
        return True
    elif all(
        is_newer(local_dep_set.EVR(), installed_dep_set.EVR())
        for installed_dep_set in installed_dep_sets
    ):
        logger.info(f"Package file {rpm_file} is newer, OK to update.")
        return True
    else:
        logger.info(
            f"Package file {rpm_file} is same or older than installed version."
        )
        return False


def can_update(rpm_file):
    trans_set = rpm.TransactionSet()
    header = readRpmHeader(trans_set, rpm_file)

    name = header[rpm.RPMTAG_NAME]
    epoch = header[rpm.RPMTAG_EPOCH]
    version = header[rpm.RPMTAG_VERSION]
    release = header[rpm.RPMTAG_RELEASE]

    local_evr = (epoch, version, release)
    logger.debug(f"local_evr={local_evr}")

    installed_evrs = [
        (
            hdr[rpm.RPMTAG_EPOCH],
            hdr[rpm.RPMTAG_VERSION],
            hdr[rpm.RPMTAG_RELEASE],
        )
        for hdr in trans_set.dbMatch("name", name)
    ]
    logger.debug(f"installed_evrs={installed_evrs}")

    if not installed_evrs:
        logger.info(f"Package '{name}' is not installed, OK to upgrade.")
        return True
    elif all(
        is_newer(local_evr, installed_evr) for installed_evr in installed_evrs
    ):
        logger.info(f"Package '{name}' is newer, OK to upgrade.")
        return True
    else:
        logger.info(
            f"Package '{name}' is same or older than installed version."
        )
        return False


def rpm_evr(path, ts):
    with open(path, "rb") as f:
        hdr = ts.hdrFromFdno(f.fileno())

    return (
        str(hdr["epoch"]),
        hdr["version"],
        hdr["release"],
    )


def sort_rpms(rpms):
    ts = rpm.TransactionSet()

    rpms_with_evr = [(path, rpm_evr(path, ts)) for path in rpms]

    rpms_with_evr.sort(
        key=functools.cmp_to_key(lambda a, b: rpm.labelCompare(a[1], b[1]))
    )

    return [path for path, _ in rpms_with_evr]


def is_queue_empty():
    host = tqcommon.get_sysconfig()["mqhost"]
    conn = pika.BlockingConnection(pika.ConnectionParameters(host=host))
    channel = conn.channel()
    queue = channel.queue_declare(
        queue="task_queue",
        durable=True,
        arguments={"x-max-priority": 10},
    )
    num_messages = queue.method.message_count
    conn.close()
    logger.debug(f"message count: {num_messages}")
    return num_messages == 0


def is_owned_by_root(path):
    return os.stat(path).st_uid == 0


def main():
    rstar_dir = tqcommon.get_rstar_dir()

    hostname = socket.gethostname().split(".")[0]
    logfile = os.path.join(
        tempfile.gettempdir(), f"tq-update-{hostname}.log.txt"
    )
    level = logging.getLevelName(os.environ.get("LOG_LEVEL", "WARNING"))
    logging.basicConfig(
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%m/%d/%Y %I:%M:%S %p",
        level=level,
        handlers=[logging.StreamHandler(), logging.FileHandler(logfile)],
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    repodir = os.path.join(rstar_dir, "repo", "publishing")
    logger.debug(f"repo dir: {repodir}")

    redhat_version = get_redhat_version()
    logger.debug(f"redhat version: {redhat_version}")
    rpmdir = os.path.join(repodir, redhat_version, "RPMS")
    logger.debug(f"rpm dir: {rpmdir}")
    rpms = sort_rpms(
        glob.glob(f"{rpmdir}{os.sep}**{os.sep}task-queue-*.rpm", recursive=True)
    )
    if not rpms:
        logger.info("No rpms found")
        return
    latest_rpm = rpms[-1]
    logger.debug(f"Latest rpm: {latest_rpm}")

    if can_update(latest_rpm) and is_queue_empty():
        script_path = os.path.join(rstar_dir, "tmp", "update-task-queue.sh")
        if not is_owned_by_root(script_path):
            logger.error(f"{script_path} mut be owned by root.")
            sys.exit(1)

        update_cmd = ["bash"]
        if logging.getLogger().isEnabledFor(logging.DEBUG):
            update_cmd.append("-x")
        update_cmd.append(script_path)
        logger.debug("update cmd: %s", shlex_join(update_cmd))

        result = subprocess.run(
            update_cmd,
            universal_newlines=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        logger.debug(f"output: {result.stdout}")
        sys.exit(result.returncode)


if __name__ == "__main__":
    main()
