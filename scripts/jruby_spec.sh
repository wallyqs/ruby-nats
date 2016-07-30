set -e

gem install bundler
gem pristine jruby-launcher --version 1.1.1
bundle install --without server
bundle exec rake spec:client:jruby
