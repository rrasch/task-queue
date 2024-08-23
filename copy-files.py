#!/usr/bin/python3

from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from filelock import Timeout, FileLock
from glob import glob
import contextlib
import json
import logging
import os
import re
import shutil
import smtplib
import subprocess
import time



# XXX: Change remote_user and local_user
REMOTE_ROOT = "/scratch/remote_user/video"

LOCAL_ROOT = "/content/prod/rstar/tmp/local_user/video"

LOGDIR = os.path.join(LOCAL_ROOT, "logs")

LOCK_FILE = "hpc.txt"


@contextlib.contextmanager
def remember_cwd():
    curdir = os.getcwd()
    try:
        yield
    finally:
        os.chdir(curdir)


def glob_re(regex):
    pass


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


def notify(attachments):
    sender = "local_user"
    receivers = [sender]
    subject = "completed"
    body = subject
    send_mail(sender, receivers, subject, body, attachments)


def move_file(path, jobid):
    with open(path) as f:
        data = json.load(f)

    output_dir = os.path.dirname(data["output_base"])
    print(output_dir)
    output_dir = output_dir[len(REMOTE_ROOT):]
    print(output_dir)

    input_dir = LOCAL_ROOT + output_dir
    print(input_dir)

    basename = os.path.basename(data["output_base"])
    checksum_file = os.path.join(input_dir, f"{basename}_md5.txt")
    print(checksum_file)
    if not os.path.isfile(checksum_file):
        return

    cwd = os.getcwd()
    os.chdir(input_dir)
    process = subprocess.run(
        ["md5sum", "--check", "--strict", checksum_file]
    )
    os.chdir(cwd)

    if process.returncode != 0:
        print("md5sum failed")
        return

    with open(checksum_file) as f:
        files = [line.split()[1] for line in f]

    print(files)

    for f in files:
        src = os.path.join(input_dir, f)
        dst = os.path.join(output_dir, f)
        print(src)
        print(dst)
        if os.path.isfile(dst):
            print(f"Video file '{dst}' already exists.")
        # shutil.move(src, dst)
        #

    # backup_file = f"{path}.backup"
    # shutil.move(path, backup_file)

    cs_file = os.path.join(input_dir, f"{basename}_contact_sheet.jpg")
    attachments = [cs_file] if os.path.isfile(cs_file) else []
    notify(attachments)


def process():
    for entry in os.listdir(LOGDIR):
        match = re.search(r"^(\d+)\.json", entry)
        if match:
            jobid = match.group(1)
            path = os.path.join(LOGDIR, entry)
            print(path)
            move_file(path, jobid)


def main():
    logging.basicConfig()
    with FileLock(LOCK_FILE, timeout=3):
        process()


if __name__ == "__main__":
    main()
