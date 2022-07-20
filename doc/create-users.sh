#!/bin/bash

getent group rstar >/dev/null || sudo groupadd -g 450 -r rstar
getent passwd rstar >/dev/null || \
  sudo useradd -r -m -u 450 -g rstar -s /sbin/nologin -c "rstar" rstar

getent group deploy >/dev/null || sudo groupadd -g 451 -r deploy
getent passwd deploy >/dev/null || \
  sudo useradd -r -m -u 451 -g deploy -s /sbin/nologin -c "deploy" deploy

getent group dlib >/dev/null || sudo groupadd dlib

