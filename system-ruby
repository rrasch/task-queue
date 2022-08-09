#!/bin/bash

# unset rvm environment
{ type -t __rvm_unload >/dev/null; } && __rvm_unload

# unset other ruby vars
unset GEM_HOME
unset GEM_PATH
unset RUBY_VERSION

exec /usr/bin/ruby "$@"
