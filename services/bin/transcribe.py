#!/usr/bin/env python3

import argparse
import logging
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from tqcommon import get_rstar_dir
from util import shlex_join

logger = logging.getLogger(__name__)


def validate_input_file(filepath):
    filepath = Path(filepath).resolve()

    if not filepath.exists():
        raise argparse.ArgumentTypeError(
            f"Input path does not exist: {filepath}"
        )

    if not filepath.is_file():
        raise argparse.ArgumentTypeError(
            f"Input path is not a file: {filepath}"
        )

    return filepath


def validate_output_file(filepath):
    filepath = Path(filepath).resolve()
    parent = filepath.parent

    if filepath.is_dir():
        raise argparse.ArgumentTypeError(
            f"Output path is a directory: {filepath}"
        )

    if not parent.is_dir():
        raise argparse.ArgumentTypeError(
            f"Output directory does not exist: {parent}"
        )

    if not os.access(parent, os.W_OK):
        raise argparse.ArgumentTypeError(
            f"Output directory is not writable: {parent}"
        )

    return filepath


def parse_traceback(output):
    if not output.startswith("Traceback"):
        return output

    lines = output.splitlines()

    for i, line in enumerate(lines[1:], start=1):
        if not line.startswith(" "):
            return "\n".join(lines[i:])

    return output


def main():
    parser = argparse.ArgumentParser(
        description="Generate SRT captions using Whisper"
    )
    parser.add_argument(
        "input_file",
        type=validate_input_file,
        help="Path to media file",
    )
    parser.add_argument(
        "output_file",
        type=validate_output_file,
        help="Output srt file",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debugging output",
    )
    args = parser.parse_args()

    logging.basicConfig(
        format="%(asctime)s %(levelname)s: %(message)s",
        datefmt="%m/%d/%Y %I:%M:%S %p",
    )

    if args.debug:
        logger.setLevel(logging.DEBUG)

    if args.output_file.exists():
        sys.exit(f"Error: output file already exists: {args.output_file}")

    rstar_tmp_dir = Path(get_rstar_dir()) / "tmp"

    whisper_dir = rstar_tmp_dir / "whisper"
    whisper_exe = whisper_dir / "venv" / "whisper" / "bin" / "whisper"
    whisper_model_dir = whisper_dir / "models"

    with tempfile.TemporaryDirectory(dir=rstar_tmp_dir) as temp_dir:
        tmp_srt = Path(temp_dir) / f"{args.input_file.stem}.srt"

        cmd = [
            str(whisper_exe),
            "--language",
            "English",
            "--fp16",
            "False",
            "--model",
            "small",
            "--model_dir",
            str(whisper_model_dir),
            "--output_dir",
            temp_dir,
            "--output_format",
            "srt",
            str(args.input_file),
        ]

        logger.debug("Running command: %s", shlex_join(cmd))

        try:
            proc = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            sys.exit(
                f"Command failed with exit status {e.returncode}:\n{e.stdout}"
            )
        except OSError as e:
            sys.exit(f"Could not run command: {e}")

        if not tmp_srt.exists():
            output = parse_traceback(proc.stdout)
            sys.exit(f"Command failed:\n{output}")

        logger.debug(f"Renaming {tmp_srt} to {args.output_file}")

        tmp_srt.rename(args.output_file)


if __name__ == "__main__":
    main()
