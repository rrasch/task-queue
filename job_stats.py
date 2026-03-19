#!/usr/bin/python3

import argparse
import logging
import pandas as pd
import subprocess
import tempfile
from pathlib import Path
from tabulate import tabulate


def parse_args():
    parser = argparse.ArgumentParser(
        description="Print job statistics from task queue"
    )
    parser.add_argument("-b", "--batch-id", help="Query jobs from batch id")
    parser.add_argument(
        "-f", "--from", dest="start_date", help="Query jobs from date"
    )
    parser.add_argument(
        "-t", "--to", dest="end_date", help="Query jobs to date"
    )
    parser.add_argument(
        "-l", "--limit", type=int, help="Limit results to this number"
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debugging"
    )
    return parser.parse_args()


def gen_csv(args, csv_path):
    script_dir = Path(__file__).resolve().parent
    ruby_wrapper = script_dir / "system-ruby"
    job_status_script = script_dir / "check-job-status.rb"

    cmd = [str(ruby_wrapper), str(job_status_script), "--csv", str(csv_path)]

    optional_args = {
        "--from": args.start_date,
        "--to": args.end_date,
        "--limit": args.limit,
        "--batch-id": args.batch_id,
        "--verbose": args.debug,
    }

    for flag, value in optional_args.items():
        if not value:
            continue
        if isinstance(value, bool):
            cmd.append(flag)
        else:
            cmd.extend([flag, str(value)])

    logging.debug("Running cmd '%s'", " ".join(cmd))
    subprocess.run(cmd, stdout=subprocess.DEVNULL, check=True)


def print_df(df):
    print(tabulate(df, df.columns))


def main():
    args = parse_args()

    logging.basicConfig(level=logging.DEBUG if args.debug else logging.WARN)

    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        csv_path = Path(tmp.name)

    try:
        gen_csv(args, csv_path)

        date_columns = ["submitted", "started", "completed"]

        df = pd.read_csv(
            csv_path,
            parse_dates=date_columns,
            date_parser=lambda x: pd.to_datetime(x, utc=True),
        )

    finally:
        csv_path.unlink()

    df[date_columns] = df[date_columns].apply(
        lambda col: col.dt.tz_convert("America/New_York")
    )

    # Compute job duration
    df["duration"] = df["completed"] - df["started"]

    # Overall duration
    earliest_submitted = df["submitted"].min()
    latest_completed = df["completed"].max()
    total_duration = latest_completed - earliest_submitted
    print(
        "Overall duration from earliest submitted to latest completed:"
        f" {total_duration}"
    )

    # Jobs completed per hour
    df["completed_hour"] = df["completed"].dt.floor("H")
    jobs_per_hour = (
        df.groupby("completed_hour").size().reset_index(name="jobs_completed")
    )
    jobs_per_hour = jobs_per_hour.sort_values("completed_hour")
    print("\nJobs completed per hour:\n")
    print_df(jobs_per_hour)

    avg_jobs_per_hour = jobs_per_hour["jobs_completed"].mean()
    print(
        f"\nAverage number of jobs completed per hour: {avg_jobs_per_hour:.2f}"
    )

    # Per-host statistics (worker_host is always present)
    df["duration_seconds"] = df["duration"].dt.total_seconds()

    per_host = (
        df.groupby("worker_host")
        .agg(
            total_duration_seconds=("duration_seconds", "sum"),
            average_duration_seconds=("duration_seconds", "mean"),
            jobs_completed=("duration_seconds", "count"),
            earliest_start=("started", "min"),
            latest_complete=("completed", "max"),
        )
        .reset_index()
    )

    # Convert back to timedelta for readability
    per_host["total_duration"] = pd.to_timedelta(
        per_host["total_duration_seconds"], unit="s"
    )
    per_host["average_duration"] = pd.to_timedelta(
        per_host["average_duration_seconds"], unit="s"
    )

    # Wall-clock duration per host (earliest start -> latest complete)
    per_host["wall_clock_duration"] = (
        per_host["latest_complete"] - per_host["earliest_start"]
    )

    # Drop intermediate seconds columns
    per_host = per_host.drop(
        columns=["total_duration_seconds", "average_duration_seconds"]
    )

    print("\nPer-host statistics:\n")
    print_df(per_host)


if __name__ == "__main__":
    main()
