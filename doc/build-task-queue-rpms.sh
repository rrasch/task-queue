#!/usr/bin/env bash

set -euo pipefail

source /etc/os-release

os_name="$ID"
os_version="$VERSION_ID"

log_file="build-${os_name}-${os_version}.log"

packages=(
    perl-Net-AMQP-RabbitMQ
    rubygem-amq-protocol
    rubygem-bunny
    rubygem-mediainfo
    rubygem-rbtree
    rubygem-servolux
	rubygem-set
    rubygem-sorted_set
    rubygem-sql-maker
)

for package in "${packages[@]}"; do
    echo "Building ${package}..."

    cd "$HOME/rpm/${package}"

    rpmbuild -bb "${package}.spec" 2>&1 | tee "$log_file"
done

createrepo --update "/content/prod/rstar/repo/publishing/$os_version"

cd "$HOME/work/task-queue/doc"
./build-rpm.sh "v0.0.0"
