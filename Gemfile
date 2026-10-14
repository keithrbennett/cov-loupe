# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Development dependencies
gem 'json_schemer', '~> 2.5', require: false
gem 'rake', '~> 13.4'
gem 'rspec', '~> 3.13'
gem 'rubocop', '~> 1.88.0'
gem 'rubocop-rspec', '~> 3.10.0'

# simplecov generates this project's own coverage.json; cov-loupe itself never
# loads it. Normal `bundle install` resolves it within the 1.x range. The "compat"
# job in .github/workflows/test.yml sets SIMPLECOV_VERSION to run the suite against
# the oldest and newest 1.x releases, so an incompatible upstream release fails
# there rather than on main.
simplecov_pin = ENV.fetch('SIMPLECOV_VERSION', '')
gem 'simplecov', '>= 1.0', '< 2.0', *([simplecov_pin] unless simplecov_pin.empty?)

# simplecov-cobertura 4.x is the line that pairs with simplecov 1.x.
gem 'simplecov-cobertura', '~> 4.0'

# Security auditing
gem 'bundler-audit', '~> 0.9', require: false
gem 'erb', '>= 6.0.4'
gem 'ruby_audit', '~> 3.1', require: false
