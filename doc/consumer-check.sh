#!/bin/bash

set -eu

EXPECTED=${1:-18}

if ! [[ "$EXPECTED" =~ ^[0-9]+$ ]]; then
    echo "Input '$EXPECTED' is not a number" >&2
    echo "Must supply an integer for expected number of consumers." >&2
    exit 1
fi

WORKDIR=$HOME/work/task-queue

MY_CNF="/content/prod/rstar/etc/my-taskqueue.cnf"

EMAIL_CNF="/content/prod/rstar/etc/email.yaml"

MAILTO=$(awk '{print $2'} $EMAIL_CNF | sort | uniq \
    | grep -v '-' | paste -sd ',' - | sed 's/,/, /g')

if [ -x /bin/s-nail ]; then
    MAIL="/bin/s-nail -M text/html"
elif [ -x /bin/mailx ]; then
    MAIL="/bin/mailx -S content_type=text/html"
else
    MAIL="/bin/mail"
fi

SCRIPT_NAME="$(basename -- "$(realpath -- "$0")")"
SCRIPT_NAME="${SCRIPT_NAME%.*}"

OUTPUT=$($WORKDIR/get-connections.py)

NUM_CONSUMERS=$(echo "$OUTPUT" | grep -v -- -- | grep -v Host | wc -l)

ERR=""

NL=$'\n'$'\n'

if [ $NUM_CONSUMERS -ne $EXPECTED ]; then
    ERR="Only $NUM_CONSUMERS task queue consumers.${NL}${OUTPUT}"
fi

JOB_ID=$(echo "SELECT job_id FROM job ORDER BY job_id DESC LIMIT 1" \
    | mysql --defaults-extra-file=$MY_CNF --skip-column-names --batch)

if ! [[ "$JOB_ID" =~ ^[0-9]+$ ]]; then
    [ -n "$ERR" ] && ERR="${ERR}${NL}"
    ERR="${ERR}There was a problem connecting to MySQL"
fi

if [ -n "$ERR" ]; then
    cat <<EOF - | /usr/sbin/sendmail -t
To: $MAILTO
Subject: task queue problem
Content-Type: text/html

<html>
<body>
<pre>
$ERR
</pre>
</body>
</html>
EOF
fi
