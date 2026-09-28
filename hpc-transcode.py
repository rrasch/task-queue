#!/usr/bin/env python3

import argparse
import json
import logging
import os
import re
import shlex
import socket
import sqlite3
import sys
from datetime import timedelta
from pathlib import Path
from pprint import pformat
from subprocess import PIPE, STDOUT, CalledProcessError, run

import paramiko
import pika
from pymediainfo import MediaInfo
from tld import get_fld

import tqcommon

SACCT_FORMAT = (
    "JobID,JobName%-90,Partition,Account,"
    "AllocCPUS,State,ExitCode,MaxVMSize,NodeList"
)

SQUEUE_FORMAT = "%.15i %.25j %.8u %.10M %.2t %.9P"

logger = logging.getLogger(__name__)


class BooleanAction(argparse.Action):
    def __init__(self, option_strings, dest, nargs=None, **kwargs):
        super().__init__(
            option_strings, dest, nargs=0, **kwargs
        )

    def __call__(self, parser, namespace, values, option_string=None):
        setattr(
            namespace,
            self.dest,
            not option_string.startswith("--no"),
        )


class ArgumentParsingError(Exception):
    pass


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ArgumentParsingError(message)


def script_paths():
    script_dir = os.path.dirname(os.path.realpath(sys.argv[0]))
    script_name = Path(sys.argv[0]).stem
    return (script_dir, script_name)


def delta_to_dict(delta):
    return {
        "days": delta.days,
        "hours": delta.seconds // 3600,
        "minutes": (delta.seconds // 60) % 60,
        "seconds": delta.seconds % 60,
        "total_hours": delta.total_seconds() / 3600,
    }


def fmt_time(seconds):
    duration = delta_to_dict(timedelta(seconds=seconds))
    logger.debug(f"duration dict: {pformat(duration)}")
    time_str = ":".join(
        f"{duration[unit]:02d}" for unit in ("hours", "minutes", "seconds")
    )
    if duration["days"] > 0:
        time_str = duration["days"] + "-" + time_str
    logger.debug(f"time: {time_str}")
    return time_str


def round_down_min(minutes, to_min=30):
    return minutes // to_min * to_min


class VideoTrackNotFound(Exception):
    __module__ = "builtins"


def duration(input_file, minutes=True):
    media_info = MediaInfo.parse(input_file)
    video_tracks = [
        track for track in media_info.tracks if track.track_type == "Video"
    ]
    if not video_tracks:
        raise VideoTrackNotFound(f"No video track found for {input_file}")
    video = video_tracks[0]
    logger.debug("data: %s", pformat(video.to_data()))
    logger.debug(
        f"Bit rate: {video.bit_rate}, Frame rate: {video.frame_rate}, "
        f"Format: {video.format}, "
        f"Duration (raw value): {video.duration} "
    )
    duration_sec = video.duration / 1000
    duration_min = duration_sec / 60
    logger.debug(f"duration: {duration_min:.3f} minutes")
    return duration_min if minutes else duration_sec


def max_time(input_file):
    duration_sec = duration(input_file, minutes=False)
    logger.debug(f"Duration of {input_file} is {duration_sec} seconds.")
    max_time_str = fmt_time(duration_sec * 5)
    return max_time_str


def root_join(*paths):
    return os.path.join(os.sep, *paths)


def clear_rsync_env():
    for name, value in os.environ.items():
        if name.startswith("RSYNC"):
            os.environ.pop(name)
            logger.debug(f"Unset var {name}='{value}'")


def escape_quote(filename):
    return filename.replace("'", r"'\''")


def abs_join(path1, path2):
    return os.path.join(path1, path2.lstrip(os.sep))


def shlex_join(split_command):
    """Return a shell-escaped string from *split_command*."""
    return " ".join(shlex.quote(arg) for arg in split_command)


def get_profiles(args_str):
    parser = ArgumentParser(allow_abbrev=False)
    parser.add_argument("--profiles_path", nargs="*")
    try:
        logger.debug(f"args_str={args_str}")
        args = parser.parse_args(shlex.split(args_str))
    except ArgumentParsingError:
        logger.exception("Error processing arguments")
        sys.exit(1)
    return args.profiles_path


def add_slurm_id(job_id, slurm_id, dbfile):
    dbconn = sqlite3.connect(dbfile)
    cursor = dbconn.cursor()
    cursor.execute(
        """UPDATE jobs
        SET slurm_id = ?, state = 'running'
        WHERE job_id = ?
        """,
        (slurm_id, job_id),
    )
    dbconn.commit()
    dbconn.close()


def do_cmd(cmdlist, **kwargs):
    logger.debug("Running command: %s", shlex_join(cmdlist))
    try:
        process = run(
            cmdlist,
            check=True,
            stdout=PIPE,
            stderr=STDOUT,
            universal_newlines=True,
            **kwargs,
        )
        logger.debug("rsync output: %s", process.stdout)
    except CalledProcessError as e:
        logger.error("%s\n%s", e, e.output)
        sys.exit(1)
    return process


def transcode(req, host, email, hpc_config):
    ssh_dir = os.path.join(os.path.expanduser("~"), ".ssh")
    config_file = os.path.join(ssh_dir, "config")
    keyfile = os.path.join(ssh_dir, "id_rsa")

    config = paramiko.SSHConfig.from_path(config_file).lookup(host)
    logger.debug("config: %s", pformat(config))

    remote_homedir = root_join("home", config["user"])

    basename = Path(req["input"]).stem
    sacct_path = root_join(remote_homedir, "bin", "sacct.sh")
    sacct = do_cmd(["ssh", host, sacct_path])
    if basename in sacct.stdout:
        logger.info(f"{basename} already running")
        return

    max_duration = max_time(req["input"])
    logger.debug(f"Max transcode duration: {max_duration}")

    rounded_duration = int(round_down_min(duration(req["input"])))
    logger.debug(f"rounded duration: {rounded_duration} minutes")
    memory = "16GB" if rounded_duration >= 120 else "8GB"

    logdir = root_join("scratch", config["user"], "logs")
    remote_script = root_join(
        "home", config["user"], "work", "hpc-transcode", "submit-one.sh"
    )
    remote_dir = root_join("scratch", config["user"], "video")
    remote_input = abs_join(remote_dir, req["input"])
    remote_output = abs_join(remote_dir, req["output"])

    profile_paths = get_profiles(req["args"])
    src_files = [req["input"]]
    for path in profile_paths:
        if os.path.isabs(path):
            src_files.append(path)

    args_list = [
        arg
        for path in profile_paths
        for arg in (
            "--profiles_path",
            abs_join(remote_dir, path) if os.path.isabs(path) else path,
        )
    ]

    job_id = req["job_id"]

    remote_cmd_list = [
        "sbatch",
        f"--output={logdir}/transcode-%j.out",
        f"--mem={memory}",
        f"--time={max_duration}",
        f"--mail-user={email}",
        remote_script,
        remote_input,
        remote_output,
        str(job_id),
        *args_list,
    ]

    remote_cmd = shlex_join(remote_cmd_list)

    logger.debug(f"remote script = {remote_script!s}")
    logger.debug(f"remote input = {remote_input!s}")
    logger.debug(f"remote cmd = {remote_cmd!s}")

    try:
        ret = run(
            [
                "/usr/bin/rsync",
                "-Rsavzhessh",
                "--progress",
                "--stats",
                "--copy-links",
                *src_files,
                f"{host}:{remote_dir}",
            ],
            check=True,
            stdout=PIPE,
            stderr=STDOUT,
            universal_newlines=True,
        )
        logger.debug("rsync output: %s", ret.stdout)
    except CalledProcessError as e:
        logger.error("%s\n%s", e, e.output)
        sys.exit(1)

    ssh = paramiko.SSHClient()
    ssh.load_system_host_keys()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        config["hostname"],
        username=config["user"],
        key_filename=keyfile,
        allow_agent=True,
    )
    _stdin, stdout, _stderr = ssh.exec_command(remote_cmd)
    stdout.channel.set_combine_stderr(True)
    status = stdout.channel.recv_exit_status()
    output = stdout.read().decode()
    for line in output.splitlines():
        logger.debug(f"output: {line}")
    ssh.close()
    logger.debug(f"Remote exit status={status}")
    if status:
        sys.exit(f"Transcoding on host {host} failed")
    match = re.search(r"Submitted batch job (\d+)", output)
    if match:
        slurm_id = int(match.group(1))
        logger.debug(f"Slurm ID = {slurm_id}")
        add_slurm_id(job_id, slurm_id, hpc_config["dbfile"])


def get_email():
    domain = get_fld(socket.gethostname(), fix_protocol=True)
    username = os.getlogin()
    return f"{username}@{domain}"


def main():
    sysconfig = tqcommon.get_sysconfig()
    hpc_config = tqcommon.get_hpc_config()

    if "mailto" in hpc_config:
        default_email = hpc_config["mailto"][0]
    else:
        default_email = get_email()

    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--host", default=hpc_config["remote_host"])
    parser.add_argument(
        "-c",
        "--count",
        type=int,
        choices=range(1, 11),
        default=1,
        help="Number of files to consume",
    )
    parser.add_argument(
        "-e",
        "--email",
        default=default_email,
        help="Email for slurm notifications",
    )
    parser.add_argument(
        "-d",
        "--debug",
        "--no-debug",
        dest="debug",
        action=BooleanAction,
        help="Enable debugging",
    )
    args = parser.parse_args()

    fmt = "%(asctime)s|%(levelname)s|%(name)s: %(message)s"
    if args.debug:
        level = {
            "default": logging.DEBUG,
            "pika": logging.WARNING,
            "paramiko.transport": logging.DEBUG,
        }
    else:
        level = {
            "default": logging.INFO,
            "pika": logging.WARNING,
            "paramiko.transport": logging.WARNING,
        }
    logging.basicConfig(
        format=fmt,
        datefmt="%m/%d/%Y %I:%M:%S %p",
        level=level["default"],
    )
    level.pop("default")
    for mod, lvl in level.items():
        logging.getLogger(mod).setLevel(lvl)

    script_dir, script_name = script_paths()
    missing_file = os.path.join(script_dir, "missing.txt")
    logger.debug(f"script dir='{script_dir}'")
    logger.debug(f"script_name='{script_name}'")
    logger.debug(f"missing file='{missing_file}'")

    clear_rsync_env()

    params = pika.ConnectionParameters(
        host=sysconfig["mqhost"], heartbeat=600, blocked_connection_timeout=600
    )
    connection = pika.BlockingConnection(params)
    channel = connection.channel()
    queue_name = "hpc_transcode"
    queue = channel.queue_declare(
        queue=queue_name, durable=True, arguments={"x-max-priority": 10}
    )
    queue_size = queue.method.message_count
    logger.debug(f"{queue_name} queue size: {queue_size}")

    for _ in range(args.count):
        method_frame, _header_frame, body = channel.basic_get(queue=queue_name)
        if not method_frame:
            logger.debug("No message available")
            break

        request = body.decode()
        logger.info(f"Processing {request}")
        req = json.loads(request)
        if not os.path.isfile(req["input"]):
            with open(missing_file, "a") as out:
                out.write(req["input"] + "\n")
        transcode(req, args.host, args.email, hpc_config)

        channel.basic_ack(method_frame.delivery_tag)
        logger.debug("Sent ack")

    connection.close()


if __name__ == "__main__":
    main()
