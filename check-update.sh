#!/bin/bash
#
# Restart task-queue when Jenkins creates updated file.

set -e

UPDATED_FILE="/var/lib/task-queue/updated"

if [ -f $UPDATED_FILE ]; then
	rm -f $UPDATED_FILE
	/usr/local/dlib/task-queue/workersctl restart
fi

