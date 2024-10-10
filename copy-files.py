#!/usr/bin/python3

from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from filelock import FileLock
from logging.handlers import RotatingFileHandler
from pprint import pformat
import MySQLdb
import argparse
import contextlib
import json
import logging
import os
import re
import shutil
import smtplib
import sqlite3
import subprocess
import sys
import tqcommon
import util


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


def notify(data, attachments, config):
    sender = config["mailfrom"]
    receivers = config["mailto"]
    subject = (
        f"hpc job {data['job_id']} completed {data['end_time']} "
        f"with exit status {data['exit_status']}"
    )
    body = subject + "\n\n" + json.dumps(data, indent=4)
    send_mail(sender, receivers, subject, body, attachments)
    # post_photo(config["iguser"], config["igpass"], attachments[0], subject)


def update_db(job_id, dbfile):
    dbconn = sqlite3.connect(dbfile)
    cursor = dbconn.cursor()
    cursor.execute(
        f"""UPDATE jobs
        SET state = 'done'
        WHERE job_id = {job_id}
        """
    )
    dbconn.commit()
    dbconn.close()


def update_task_queue_db(data):
    config = tqcommon.get_myconfig()
    conn = MySQLdb.connect(
        host=config["host"],
        database=config["database"],
        user=config["user"],
        password=config["password"],
        connect_timeout=10,
    )
    cursor = conn.cursor()
    num_rows = cursor.execute(
        """UPDATE job
        SET started = %s, completed = %s
        WHERE job_id = %s
        """,
        (
            data["start_time"],
            data["end_time"],
            data["job_id"],
        ),
    )
    cursor.close()
    conn.close()
    return num_rows


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
            logging.info(f"Video file '{dst}' already exists.")
        else:
            shutil.move(src, dst)
            os.chmod(dst, 0o644)

    backup_file = f"{path}.backup"
    shutil.move(path, backup_file)

    update_db(data["job_id"], config["dbfile"])

    cmd = get_ssh(config, for_rsync=False) + [f"~/bin/cleanup {data['job_id']}"]
    output = do_cmd(cmd, stderr=subprocess.STDOUT)
    logging.debug(f"cleanup output: {output}")

    cs_file = os.path.join(input_dir, f"{basename}_contact_sheet.jpg")
    attachments = [cs_file] if os.path.isfile(cs_file) else []
    notify(data, attachments, config)


def process(config):
    for entry in os.listdir(config["logdir"]):
        path = os.path.join(config["logdir"], entry)
        match = re.search(r"^(\d+)\.json$", entry)
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


def get_ssh(config, for_rsync=True):
    ssh = [
        "/usr/bin/ssh",
        "-i",
        config["ssh_key"],
        "-o",
        "PreferredAuthentications=publickey",
        "-o",
        "IdentitiesOnly=yes",
    ]
    if for_rsync:
        return util.shlex_join(ssh)
    else:
        ssh.append(config["remote_host"])
        return ssh


def sync_fs(config):
    output = do_cmd(
        [
            "/usr/bin/rsync",
            "-avz",
            "-e",
            get_ssh(config, for_rsync=True),
            "--delete",
            "--exclude=*.mov",
            "--exclude=.*",
            f"{config['remote_host']}:{config['remote_dir']}/",
            config["local_dir"],
        ],
        stderr=subprocess.STDOUT,
    )
    logging.debug("rsync output: %s", output)


def validate_filepath(filepath):
    """Validates a filepath and returns it if valid."""
    if not os.path.exists(filepath):
        raise argparse.ArgumentTypeError(f"File not found: '{filepath}'")
    return filepath


def validate_email(email):
    if not re.search(
        r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$", email
    ):
        raise argparse.ArgumentTypeError(f"'{email}' is not a valid email")
    return value


def main():
    script_name, ext = os.path.splitext(
        os.path.basename(os.path.realpath(sys.argv[0]))
    )
    default_logfile = os.path.join(
        tqcommon.get_rstar_dir(), "tmp", f"{script_name}.log"
    )

    parser = argparse.ArgumentParser(description="Add video jobs to hpc queue")
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debugging"
    )
    parser.add_argument("-l", "--logfile", default=default_logfile)
    parser.add_argument("-k", "--keyfile", type=validate_filepath)
    parser.add_argument("--no-sync", action="store_true")
    parser.add_argument(
        "-e", "--email", type=validate_email, help="Email for notifications"
    )
    args = parser.parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    file_handler = RotatingFileHandler(
        args.logfile, maxBytes=10 * 1024 * 1024, backupCount=3
    )
    logging.basicConfig(
        format="%(asctime)s|%(levelname)s: %(message)s",
        datefmt="%m/%d/%Y %I:%M:%S %p",
        level=level,
        handlers=[logging.StreamHandler(), file_handler],
    )

    config = tqcommon.get_hpc_config()
    if args.keyfile:
        config["ssh_key"] = args.keyfile
    if args.email:
        config["mailto"] = [args.email]

    with FileLock(config["lock_file"], timeout=3):
        if not args.no_sync:
            sync_fs(config)
        process(config)


if __name__ == "__main__":
    main()
