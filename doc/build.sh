#!/bin/bash

set -e

rm -vf $HOME/rpm/RPMS/task-queue-*rpm

rpmbuild --bb --without ruby task-queue.spec 2>&1 | tee build2.log

sudo dnf -y remove task-queue

sleep 60
 
sudo dnf -y install $HOME/rpm/RPMS/task-queue-*.rpm

