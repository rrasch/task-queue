#!/bin/bash
#
# Restart task-queue when Jenkins creates .updated file.

set -e

PROG=$(readlink -f $0)

TQHOME=$(dirname $PROG)

UPDATED_FILE="$TQHOME/.updated"

if [ -f $UPDATED_FILE ] ; then
	rm -f $UPDATED_FILE
	$TQHOME/workersctl restart
fi

