#!/usr/bin/python3

from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from filelock import Timeout, FileLock
from logging.handlers import RotatingFileHandler
from pprint import pformat
import argparse
import contextlib
import json
import logging
import os
import re
import shutil
import smtplib
import subprocess
import sys
import tqcommon


@contextlib.contextmanager
def remember_cwd():
    curdir = os.getcwd()
    try:
        yield
    finally:
        os.chdir(curdir)


def send_mail(sender, receivers, subject, body, attachments=[]):
    msg = MIMEMultipart()
    msg["From"] = sender
    msg["To"] = ", ".join(receivers)
    msg["Subject"] = subject

    msg.attach(MIMEText(body, "plain", "utf-8"))
    for attachment in attachments:
        basename = os.path.basename(attachment)
        with open(attachment, "rb") as f:
            part = MIMEApplication(f.read(), Name=basename)
        part["Content-Disposition"] = f"attachment; filename={basename}"
        msg.attach(part)

    smtp = smtplib.SMTP("localhost")
    smtp.sendmail(sender, receivers, msg.as_string())
    smtp.quit()


def post_photo(user, pwd, img_file, caption):
    cl = Client()
    # adds a random delay between 1 and 3 seconds after each request
    cl.delay_range = [1, 3]

    cred_file = os.path.join(os.path.expanduser("~"), "instagrapi-creds.json")

    if os.path.exists(cred_file):
        cl.load_settings(cred_file)
        cl.login(user, pwd)
        cl.get_timeline_feed()  # check session
    else:
        cl.login(user, pwd)
        cl.dump_settings(cred_file)

    media = cl.photo_upload(path=img_file, caption=caption)
    logging.debug("media: %s", pformat(media))


def notify(attachments, config):
    sender = config["mailfrom"]
    receivers = config["mailto"]
    subject = "completed"
    body = subject
    send_mail(sender, receivers, subject, body, attachments)
    # post_photo(config["iguser"], config["igpass"], attachments[0], subject)


def move_file(path, jobid, config):
    with open(path) as f:
        data = json.load(f)

    output_dir = os.path.dirname(data["output_base"])
    logging.debug(f"output_dir: {output_dir}")
    output_dir = output_dir[len(config["remote_dir"]) :]
    logging.debug(f"output_dir: {output_dir}")

    input_dir = config["local_dir"] + output_dir
    logging.debug(f"input_dur: {input_dir}")

    basename = os.path.basename(data["output_base"])
    checksum_file = os.path.join(input_dir, f"{basename}_md5.txt")
    logging.debug(f"checksum file: {checksum_file}")
    if not os.path.isfile(checksum_file):
        return

    cwd = os.getcwd()
    os.chdir(input_dir)
    process = subprocess.run(
        ["/usr/bin/md5sum", "--check", "--strict", checksum_file]
    )
    os.chdir(cwd)

    if process.returncode != 0:
        logging.error(f"md5sum failed for {checksum_file}")
        return

    with open(checksum_file) as f:
        files = [line.split()[1] for line in f]

    logging.debug("files: %s", pformat(files))

    for f in files:
        src = os.path.join(input_dir, f)
        dst = os.path.join(output_dir, f)
        logging.debug(f"src file: {src}")
        logging.debug(f"dst file: {dst}")
        if os.path.isfile(dst):
            print(f"Video file '{dst}' already exists.")
        else:
            shutil.move(src, dst)

    backup_file = f"{path}.backup"
    shutil.move(path, backup_file)

    cs_file = os.path.join(input_dir, f"{basename}_contact_sheet.jpg")
    attachments = [cs_file] if os.path.isfile(cs_file) else []
    notify(attachments, config)


def process(config):
    for entry in os.listdir(config["logdir"]):
        path = os.path.join(config["logdir"], entry)
        match = re.search(r"^(\d+)\.json", entry)
        if match:
            jobid = match.group(1)
            logging.debug(f"logfile: {path}")
            move_file(path, jobid, config)


def do_cmd(cmd, stderr=subprocess.PIPE):
    process = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=stderr,
        universal_newlines=True,
    )
    return process.stdout.strip()


def set_env():
    userid = os.getlogin()
    if "SSH_AUTH_SOCK" not in os.environ:
        os.environ["SSH_AUTH_SOCK"] = do_cmd(
            ["find", "/tmp", "-user", userid, "-name", "agent.*"]
        )
    if "SSH_AGENT_PID" not in os.environ:
        os.environ["SSH_AGENT_PID"] = do_cmd(
            ["pgrep", "-u", userid, "ssh-agent"]
        )
    if not (os.environ["SSH_AUTH_SOCK"] and os.environ["SSH_AGENT_PID"]):
        sys.exit("ssh-agent not running")


def sync_fs(config):
    # set_env()
    ssh = [
        "/usr/bin/ssh",
        "-i",
        config["ssh_key"],
        "-o",
        "PreferredAuthentications=publickey",
        "-o",
        "IdentitiesOnly=yes",
    ]
    ssh = " ".join(ssh)

    output = do_cmd(
        [
            "/usr/bin/rsync",
            "-avz",
            "-e",
            ssh,
            "--delete",
            "--exclude=*.mov",
            "--exclude=.*",
            f"{config['remote_host']}:{config['remote_dir']}/",
            config["local_dir"],
        ],
        stderr=subprocess.STDOUT,
    )
    logging.debug("rsync output: %s", output)


def main():
    parser = argparse.ArgumentParser(description="Add video jobs to hpc queue")
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debugging"
    )
    args = parser.parse_args()

    script_name, ext = os.path.splitext(
        os.path.basename(os.path.realpath(sys.argv[0]))
    )

    level = logging.DEBUG if args.debug else logging.INFO
    logfile = os.path.join(
        tqcommon.get_rstar_dir(), "tmp", f"{script_name}.log"
    )
    # file_handler = logging.FileHandler(logfile)
    file_handler = RotatingFileHandler(
        logfile, maxBytes=10 * 1024 * 1024, backupCount=3
    )
    logging.basicConfig(
        format="%(asctime)s|%(levelname)s: %(message)s",
        datefmt="%m/%d/%Y %I:%M:%S %p",
        level=level,
        handlers=[logging.StreamHandler(), file_handler],
    )

    config = tqcommon.get_hpc_config()

    with FileLock(config["lock_file"], timeout=3):
        sync_fs(config)
        process(config)


if __name__ == "__main__":
    main()
