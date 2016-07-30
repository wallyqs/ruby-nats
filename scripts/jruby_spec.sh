set -e

gem install bundler
gem pristine jruby-launcher --version 1.1.1
export PATH=$HOME/gnatsd:$PATH
