#!/bin/bash

set -u

RUBY_VER=2.7.2

# unset rvm environment
{ type -t __rvm_unload >/dev/null; } && __rvm_unload

# unset other ruby vars
unset GEM_HOME
unset GEM_PATH
unset RUBY_VERSION

rm -rfv ruby-${RUBY_VER}
tar zxvf ruby-${RUBY_VER}.tar.gz
cd ruby-${RUBY_VER}

CFLAGS="${CFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches   -m64 -mtune=generic}" ; export CFLAGS ; 
CXXFLAGS="${CXXFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches   -m64 -mtune=generic}" ; export CXXFLAGS ; 
FFLAGS="${FFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches   -m64 -mtune=generic -I/usr/lib64/gfortran/modules}" ; export FFLAGS ; 
FCFLAGS="${FCFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches   -m64 -mtune=generic -I/usr/lib64/gfortran/modules}" ; export FCFLAGS ; 
LDFLAGS="${LDFLAGS:--Wl,-z,relro }"; export LDFLAGS; 

# for i in $(find . -name config.guess -o -name config.sub) ; do 
#     [ -f /usr/lib/rpm/redhat/$(basename $i) ] && /usr/bin/rm -f $i && /usr/bin/cp -fv /usr/lib/rpm/redhat/$(basename $i) $i ; 
# done ; 

./configure \
	--build=x86_64-redhat-linux-gnu \
	--host=x86_64-redhat-linux-gnu \
	--disable-dependency-tracking \
	--disable-install-doc \
	--enable-shared \
	--prefix=/usr/local/dlib/task-queue/ruby

make

