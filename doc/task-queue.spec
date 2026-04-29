%if 0%{?rhel} && 0%{?rhel} <= 8
%bcond_without cgroup_v1
%else
%bcond_with cgroup_v1
%endif

%{!?git_tag:%{error:git_tag macro must be defined}}
%{!?git_commit:%{error:git_commit macro must be defined}}

%global name     task-queue
%global version  %(echo %{git_tag} | sed 's/^v//')
%global release  1.dlts.git%{git_commit}%{?dist}
%global repourl  https://github.com/rrasch/%{name}
%global dlibdir  /usr/local/dlib/%{name}

%global tqbuilddir %{_builddir}/%{name}-%{version}

%global __brp_mangle_shebangs_exclude_from .rb$
%global __requires_exclude ^(user|group)

Summary:        Run jobs in parallel using RabbitMQ.
Name:           %{name}
Version:        %{version}
Release:        %{release}
License:        NYU DLTS
Vendor:         NYU DLTS (rasan@nyu.edu)
Group:          System Environment/Daemons
URL:            https://github.com/rrasch/%{name}
%if 0%{!?_without_ruby:1}
Source:         task-queue-ruby.tar.bz2
%else
Requires:       rubygem-amq-protocol
Requires:       rubygem-bunny
Requires:       rubygem-chronic
Requires:       rubygem-mediainfo
Requires:       rubygem-mysql2
Requires:       rubygem-rbtree
Requires:       rubygem-servolux
Requires:       rubygem-sorted_set >= 1.0.2
Requires:       rubygem-sql-maker
%endif
BuildRoot:      %{_tmppath}/%{name}-root
BuildRequires:  git
%if %{with cgroup_v1}
Requires:       libcgroup-tools
Requires:       libcgroup
%endif
BuildRequires:  golang-bin
%if 0%{?fedora} > 0
BuildRequires:  golang-github-sql-driver-mysql-devel
BuildRequires:  golang-gopkg-ini-1-devel
BuildRequires:  golang-github-google-shlex-devel
%endif
%if 0%{?centos} > 0
BuildRequires:  golang-github-go-ini-ini-devel
%endif
BuildRequires:  perl-generators
Requires:       fortune-mod
Requires:       iputils
Requires:       jq
Requires:       perl-DBD-MySQL
Requires:       python3-mysqlclient
Requires:       python3-pika
Requires:       python3-psutil
Requires:       python3-tabulate
Requires:       python3-tomli
Provides:       user(rstar)
Provides:       group(dlib)
Provides:       %{dlibdir}/system-ruby

%description
%{summary}

%prep
%setup -c -T

%build

%install
rm -rf %{buildroot}

git clone %{url}.git %{buildroot}%{dlibdir}
cd %{buildroot}%{dlibdir}
%if "%{git_tag}" != "v0.0.0"
git -c advice.detachedHead=false checkout %{git_tag}
%endif

rm -rf %{buildroot}%{dlibdir}/.git*
rm -rf %{buildroot}%{dlibdir}/.rubocop.yml
find %{buildroot}%{dlibdir} -type d | xargs chmod 0755
find %{buildroot}%{dlibdir} -type f | xargs chmod 0644
find %{buildroot}%{dlibdir} -maxdepth 1 -regextype posix-extended \
    -regex '.*\.(pl|py|rb|sh)' | xargs chmod 0755
chmod 0755 %{buildroot}%{dlibdir}/workersctl
chmod 0755 %{buildroot}%{dlibdir}/log-job-status-ctl
chmod 0644 %{buildroot}%{dlibdir}/tqcommon.py
chmod 0644 %{buildroot}%{dlibdir}/util.py

# build outside of buildroot to avoid check-buildroot error
cp rerun.go %{tqbuilddir}
pushd %{tqbuilddir}

# clone shlex repo since there is no rpm for rhel
%if 0%{?rhel} > 0
mkdir -p %{tqbuilddir}/gopath/src/github.com/google
pushd %{tqbuilddir}/gopath/src/github.com/google
git clone https://github.com/google/shlex.git
popd
%endif

export GO111MODULE=off
export GOPATH=%{tqbuilddir}/gopath:$HOME/go:/usr/share/gocode
go build -trimpath -ldflags="-s -w" rerun.go
install -m 0755 rerun %{buildroot}%{dlibdir}/rerun
popd

mkdir -p %{buildroot}%{_bindir}
ln -s ../..%{dlibdir}/add-mb-job.py %{buildroot}%{_bindir}/add-mb-job
ln -s ../..%{dlibdir}/check-job-status.rb \
    %{buildroot}%{_bindir}/check-job-status
ln -s gen-job-report.rb \
    %{buildroot}%{dlibdir}/gen-job-report
ln -s ../..%{dlibdir}/log-job-status.rb \
    %{buildroot}%{_bindir}/log-job-status
ln -s ../..%{dlibdir}/rerun \
    %{buildroot}%{_bindir}/rerun-mb-job

install -D -m 0644 doc/%{name}.service %{buildroot}%{_unitdir}/%{name}.service
install -D -m 0644 doc/log-job-status.service \
    %{buildroot}%{_unitdir}/log-job-status.service

install -D -m 0644 doc/%{name}.cron %{buildroot}/etc/cron.d/%{name}
install -D -m 0644 conf/logrotate.conf %{buildroot}/etc/logrotate.d/task-queue

mkdir -p -m 0700 %{buildroot}%{_var}/lib/%{name}

mkdir -p -m 0700 %{buildroot}%{_var}/log/%{name}

%if %{with cgroup_v1}
install -D -m 0644 conf/cpulimited.conf \
    %{buildroot}%{_sysconfdir}/cgconfig.d/cpulimited.conf
%else
sed -i \
    -e '\|ExecStartPre=|i ExecStartPre=+%{dlibdir}/set_cpu_quota.sh' \
    -e '\|cgconfig.service|d' \
    %{buildroot}%{_unitdir}/%{name}.service
%endif

%if 0%{!?_without_ruby:1}
chmod 0755 %{buildroot}%{dlibdir}/rubywrap
find . -name '*.rb' | xargs perl -pi -e \
    "s,#!/usr/bin/env ruby,#!%{dlibdir}/rubywrap,"
mkdir -p %{buildroot}%{dlibdir}/ruby
tar -jvxf %{SOURCE0} -C %{buildroot}%{dlibdir} \
    --exclude=doc \
    --exclude=gem_make.out \
    --exclude='*.log' \
    --exclude=executable-hooks-uninstaller
find %{buildroot}%{dlibdir}/ruby -name racc2y -o -name y2racc \
    | xargs perl -pi -e \
    "s,#!/usr/local/bin/ruby,#!%{dlibdir}/ruby/bin/ruby,"
%else
chmod 0755 %{buildroot}%{dlibdir}/system-ruby
find . -name '*.rb' | xargs perl -pi -e \
    "s,#!/usr/bin/env ruby,#!%{dlibdir}/system-ruby,"
%endif


%pre
if ! id rstar >/dev/null 2>&1; then
    echo "ERROR: user 'rstar' must exist before installing this package." >&2
    exit 1
fi

if ! getent group dlib >/dev/null; then
    echo "ERROR: group 'dlib' must exist before installing this package." >&2
    exit 1
fi

rm -f /etc/logrotate.d/taskqueue*

if [ "$1" = "2" ]; then
    systemctl stop task-queue
    systemctl stop log-job-status
fi
exit 0


%post
systemctl enable task-queue.service
systemctl daemon-reload

%if %{with cgroup_v1}
if ! grep -qs 'group cpulimited' /etc/cgconfig.conf; then
    echo >> /etc/cgconfig.conf
    cat /etc/cgconfig.d/cpulimited.conf >> /etc/cgconfig.conf
else
    perl -pi.bak -e 's/(cpu.cfs_quota_us\s+=\s+)\d+;/${1}2000000;/g' /etc/cgconfig.conf
fi
systemctl restart cgconfig
%endif

LOGDIR="/content/prod/rstar/tmp/mdi/task-queue/logs"

if ! grep -qs `hostname -s` /etc/logrotate.d/task-queue; then
  perl -pi -e "s,{,${LOGDIR}/`hostname -s`/*.log {," /etc/logrotate.d/task-queue
fi

semanage fcontext -d "${LOGDIR}(/.*)?" 2>/dev/null
semanage fcontext -a -t var_log_t "${LOGDIR}(/.*)?"
restorecon -R $LOGDIR

echo <<EOF
********************************************************************
    Please read

    %{dlibdir}/doc/INSTALL.md

    for post-installation instructions.
********************************************************************
EOF
exit 0


%preun
if [ "$1" = "0" ]; then
    systemctl stop task-queue
    systemctl stop log-job-status
    systemctl disable task-queue.service
    systemctl disable log-job-status.service
    systemctl daemon-reload
else
    systemctl enable task-queue
    systemctl daemon-reload
fi
exit 0


%postun


%clean
rm -rf %{buildroot}


%files
%defattr(-, root, root)
%{dlibdir}
%{_bindir}/*
%{_unitdir}/*
/etc/cron.d/%{name}
%config(noreplace) /etc/logrotate.d/task-queue
%if %{with cgroup_v1}
%config(noreplace) /etc/cgconfig.d/cpulimited.conf
%endif
%attr(0750,rstar,dlib) %{_var}/lib/%{name}
%attr(0750,rstar,dlib) %{_var}/log/%{name}


%changelog
* Sun Mar 22 2026 Rasan Rasch <rasan@nyu.edu> - 1.5.2-1
- add video:convert_iso
