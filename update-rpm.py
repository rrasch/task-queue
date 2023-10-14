#!/usr/bin/env python3

import functools
import glob
import logging
import os
import rpm
import socket
import subprocess
import time
import tqcommon


print = functools.partial(print, flush=True)


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


def is_newer(version1, version2):
    logging.debug(f"comparing {version1} to {version2}")
    return version1 > version2


def can_upgrade(rpm_file):
    trans_set = rpm.TransactionSet()
    local_header = readRpmHeader(trans_set, rpm_file)
    local_dep_set = local_header.dsOfHeader()
    name = local_header["name"]
    installed_dep_sets = [
        hdr.dsOfHeader() for hdr in trans_set.dbMatch("name", name)
    ]
    if not installed_dep_sets:
        logging.info(f"{name} is not installed, OK to upgrade.")
        return True
    elif all(
        [
            is_newer(local_dep_set.EVR(), installed_dep_set.EVR())
            for installed_dep_set in installed_dep_sets
        ]
    ):
        logging.info(f"Package file {rpm_file} is newer, OK to upgrade.")
        return True
    else:
        logging.info(
            f"Package file {rpm_file} is same or older than installed version."
        )
        return False


def main():
    level = logging.getLevelName(os.environ.get("LOG_LEVEL", "WARNING"))
    logging.basicConfig(format="%(levelname)s: %(message)s", level=level)

    rstar_dir = tqcommon.get_rstar_dir()
    repodir = os.path.join(rstar_dir, "repo", "publishing")
    logging.debug(f"{repodir=}")

    redhat_version = get_redhat_version()
    logging.debug(f"{redhat_version=}")
    rpmdir = os.path.join(repodir, redhat_version, "RPMS")
    logging.debug(f"{rpmdir=}")
    rpms = sorted(
        glob.glob(
            f"{rpmdir}{os.sep}**{os.sep}task-queue-*.rpm", recursive=True
        ),
        key=os.path.getmtime,
    )
    if not rpms:
        print("No rpms found")
        return
    latest_rpm = rpms[-1]

    if can_upgrade(latest_rpm):
        upgrade_cmd = ["bash"]
        if logging.getLogger().isEnabledFor(logging.DEBUG):
            upgrade_cmd.append("-x")
        upgrade_cmd.append(
            os.path.join(rstar_dir, "tmp", "update-task-queue.sh")
        )
        logging.debug(f"{upgrade_cmd=}")
        subprocess.run(upgrade_cmd, check=True)


if __name__ == "__main__":
    main()
