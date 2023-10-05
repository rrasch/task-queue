%define __brp_mangle_shebangs_exclude_from .rb$

%define name     task-queue
%define version  1.4.2
%define repourl  https://github.com/rrasch/%{name}
%define gitdate  %(date +"%Y%m%d")
%define commit   %(get-commit-id.sh %{repourl})
%define release  1.dlts.git.%{gitdate}.%{commit}%{?dist}
%define dlibdir  /usr/local/dlib/%{name}

%if 0%{?fedora} >= 15 || 0%{?rhel} >= 7
%define _with_systemd 1
%endif

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
Requires:       rubygem-servolux
Requires:       rubygem-sql-maker
%endif
BuildRoot:      %{_tmppath}/%{name}-root
%if 0%{?fedora} > 0 || 0%{?rhel} > 0
BuildRequires:  git
%if 0%{?fedora} >= 28 || 0%{?rhel} >= 7
Requires:       libcgroup-tools
%else
Requires:       libcgroup
%endif
%else
Requires:       /bin/cgexec
%endif
BuildRequires:  golang-bin
%if 0%{?fedora} >= 31
BuildRequires:  golang-github-sql-driver-mysql-devel
BuildRequires:  golang-gopkg-ini-1-devel
%endif
%if 0%{?centos} > 0
BuildRequires:  golang-github-go-ini-ini-devel
%endif
BuildRequires:  perl-generators
Requires:       fortune-mod
Requires:       iputils
Requires:       jq
Requires:       perl-DBD-MySQL
%if 0%{?fedora} >= 28 || 0%{?rhel} >= 8
Requires:       python3-pika
%endif

%description
%{summary}

%prep
%setup -c -T

%build

%install
rm -rf %{buildroot}

git clone %{url}.git %{buildroot}%{dlibdir}
cd  %{buildroot}%{dlibdir}
# rm -rf %{buildroot}%{dlibdir}/.git*
find %{buildroot}%{dlibdir} -type d | xargs chmod 0755
find %{buildroot}%{dlibdir} -type f | xargs chmod 0644
find %{buildroot}%{dlibdir} -maxdepth 1 -regextype posix-extended \
        -regex '.*\.(pl|py|rb|sh)' | xargs chmod 0755
chmod 0755 %{buildroot}%{dlibdir}/workersctl
chmod 0755 %{buildroot}%{dlibdir}/log-job-status-ctl

%define builddir %{_builddir}/%{name}-%{version}
export GO111MODULE=off
export GOPATH=$HOME/go:/usr/share/gocode
cp rerun.go %builddir
pushd %builddir
go build -ldflags="-s -w" rerun.go
install -m 0755 rerun %{buildroot}%{dlibdir}/rerun
popd

mkdir -p %{buildroot}%{_bindir}
ln -s %{dlibdir}/add-mb-job.pl %{buildroot}%{_bindir}/add-mb-job
ln -s %{dlibdir}/check-job-status.rb \
	%{buildroot}%{_bindir}/check-job-status
ln -s %{dlibdir}/log-job-status.rb \
	%{buildroot}%{_bindir}/log-job-status
ln -s %{dlibdir}/rerun \
	%{buildroot}%{_bindir}/rerun-mb-job

%if 0%{?_with_systemd:1}
install -D -m 0644 doc/%{name}.service %{buildroot}%{_unitdir}/%{name}.service
install -D -m 0644 doc/log-job-status.service \
        %{buildroot}%{_unitdir}/log-job-status.service
%else
install -D -m 0755 workersctl %{buildroot}%{_initrddir}/%{name}
install -D -m 0755 log-job-status-ctl \
        %{buildroot}%{_initrddir}/log-job-status
%endif
install -D -m 0644 doc/%{name}.cron %{buildroot}/etc/cron.d/%{name}
install -D -m 0644 conf/logrotate.conf %{buildroot}/etc/logrotate.d/task-queue

mkdir -p -m 0700 %{buildroot}%{_var}/lib/%{name}

mkdir -p -m 0700 %{buildroot}%{_var}/log/%{name}

install -D -m 0644 conf/cpulimited.conf \
        %{buildroot}%{_sysconfdir}/cgconfig.d/cpulimited.conf

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
rm -f /etc/logrotate.d/taskqueue*
if [ "$1" = "2" ]; then
  if [ -f /etc/redhat-release ]; then
    if [[ -n `grep -i fedora /etc/redhat-release` && `cat /etc/redhat-release|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -gt 14 ]] || [[ -n `egrep -i 'CentOS|Red Hat Ent' /etc/redhat-release` && `cat /etc/redhat-release | cut -d"." -f1|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -gt 6 ]]; then
      service task-queue stop
      service log-job-status stop
    else
      /etc/init.d/task-queue stop
      /etc/init.d/log-job-status stop
    fi
  else
    /etc/init.d/task-queue stop
    /etc/init.d/log-job-status stop
  fi
fi
exit 0

%post
# Check if release is systemd based and add plex service accordingly.
if [ -f /etc/redhat-release ]; then
  if [[ -n `grep -i fedora /etc/redhat-release` && `cat /etc/redhat-release|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -lt 15 ]] || [[ -n `egrep -i 'CentOS|Red Hat Ent' /etc/redhat-release` && `cat /etc/redhat-release | cut -d"." -f1|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -lt 7 ]]; then
     chkconfig --add task-queue
     service cgconfig restart
  else
     systemctl enable task-queue.service
     systemctl daemon-reload
     if ! grep -qs 'group cpulimited' /etc/cgconfig.conf; then
       echo >> /etc/cgconfig.conf
       cat /etc/cgconfig.d/cpulimited.conf >> /etc/cgconfig.conf
     else
       perl -pi.bak -e 's/(cpu.cfs_quota_us\s+=\s+)\d+;/${1}2000000;/g' /etc/cgconfig.conf
     fi
     systemctl restart cgconfig
  fi
fi
if ! grep -qs `hostname -s` /etc/logrotate.d/task-queue; then
  perl -pi -e "s,{,/content/prod/rstar/tmp/mdi/task-queue/logs/`hostname -s`/*.log {," /etc/logrotate.d/task-queue
fi
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
  if [ -f /etc/redhat-release ]; then
    if [[ -n `grep -i fedora /etc/redhat-release` && `cat /etc/redhat-release|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -gt 14 ]] || [[ -n `egrep -i 'CentOS|Red Hat Ent' /etc/redhat-release` && `cat /etc/redhat-release | cut -d"." -f1|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -gt 6 ]]; then
      service task-queue stop
      service log-job-status stop
    else
      /etc/init.d/task-queue stop
      /etc/init.d/log-job-status stop
    fi
  else
    /etc/init.d/task-queue stop
    /etc/init.d/log-job-status stop
  fi
fi

if [ "$1" = "0" ]; then
  if [ -f /etc/redhat-release ]; then
    if [[ -n `grep -i fedora /etc/redhat-release` && `cat /etc/redhat-release|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -lt 15 ]] || [[ -n `egrep -i 'CentOS|Red Hat Ent' /etc/redhat-release` && `cat /etc/redhat-release | cut -d"." -f1|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -lt 7 ]]; then
      chkconfig --del task-queue
      chkconfig --del log-job-status
    else
      systemctl disable task-queue.service
      systemctl disable log-job-status.service
      systemctl daemon-reload
    fi
  fi
else
  if [ -f /etc/redhat-release ]; then
    if [[ -n `grep -i fedora /etc/redhat-release` && `cat /etc/redhat-release|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -gt 14 ]] || [[ -n `egrep -i 'CentOS|Red Hat Ent' /etc/redhat-release` && `cat /etc/redhat-release | cut -d"." -f1|sed 's/[^0-9]*\([0-9]\+\).*/\1/'` -gt 6 ]]; then
      systemctl enable task-queue
      systemctl daemon-reload
    fi
  fi
fi
exit 0

%postun


%clean
rm -rf %{buildroot}

%files
%defattr(-, root, root)
#attr(-,deploy,deploy) {dlibdir}
%{dlibdir}
%{_bindir}/*
%if 0%{?_with_systemd:1}
%{_unitdir}/*
%else
%{_initrddir}/*
%endif
/etc/cron.d/%{name}
%config(noreplace) /etc/logrotate.d/task-queue
%config(noreplace) /etc/cgconfig.d/cpulimited.conf
%attr(0750,rstar,dlib) %{_var}/lib/%{name}
%attr(0750,rstar,dlib) %{_var}/log/%{name}

%changelog

# vim: et nowrap:
