#!/usr/bin/env python3

import argparse
import logging
import os
import time

import humanreadable as hr
from faster_whisper import WhisperModel

logger = logging.getLogger(__name__)


def format_timestamp(seconds: float) -> str:
    total_seconds = int(seconds)
    millis = int((seconds - total_seconds) * 1000)

    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    secs = total_seconds % 60

    return f"{hours:02}:{minutes:02}:{secs:02},{millis:03}"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Transcribe audio/video to SRT using faster-whisper."
    )

    parser.add_argument("input_file", help="Input audio or video file")

    parser.add_argument(
        "-o",
        "--output",
        help="Output SRT filename (default: same name as input with .srt)",
    )

    parser.add_argument(
        "-m",
        "--model",
        default="small",
        help="Whisper model to use (default: small)",
    )

    parser.add_argument(
        "-c",
        "--cache-dir",
        help="Models cache directory",
    )

    parser.add_argument(
        "-d",
        "--debug",
        action="store_true",
        help="Enable debugging messages",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    logging.basicConfig(format="%(levelname)s: %(message)s")

    if args.debug:
        logger.setLevel(logging.DEBUG)

    input_file = args.input_file

    if args.output:
        output_file = args.output
    else:
        base_name = os.path.splitext(input_file)[0]
        output_file = base_name + ".srt"

    start_time = time.monotonic()

    logger.debug(f"Loading model: {args.model}")
    model = WhisperModel(
        args.model, compute_type="int8", download_root=args.cache_dir
    )

    logger.debug("Transcribing...")
    segments, info = model.transcribe(input_file)

    logger.debug(
        f"Detected language '{info.language}' with probability "
        f"{info.language_probability}"
    )

    with open(output_file, "w", encoding="utf-8") as f:
        for i, segment in enumerate(segments, 1):
            start = format_timestamp(segment.start)
            end = format_timestamp(segment.end)
            text = segment.text.strip()

            f.write(f"{i}\n")
            f.write(f"{start} --> {end}\n")
            f.write(f"{text}\n\n")

    logger.debug(f"Subtitles written to: {output_file}")

    elapsed = time.monotonic() - start_time
    t = hr.Time(str(elapsed), default_unit=hr.Time.Unit.SECOND)
    logger.debug(f"Faster whisper completed in {t.to_humanreadable()}")


if __name__ == "__main__":
    main()
