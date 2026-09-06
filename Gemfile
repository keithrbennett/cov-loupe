# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Development dependencies
gem 'rake', '~> 13.4'
gem 'rspec', '~> 3.13'
gem 'rubocop', '~> 1.88.0'
gem 'rubocop-rspec', '~> 3.10.0'

# simplecov is a runtime dependency, constrained by the gemspec (>= 0.21, < 2.0).
# Normal `bundle install` leaves it unpinned here and Bundler resolves it via the
# gemspec + lockfile. The "compat" job in .github/workflows/test.yml sets
# SIMPLECOV_VERSION to run the suite against the oldest and newest versions the
# gemspec allows, so an incompatible upstream release is caught in that job
# instead of on main after a routine `bundle update`.
simplecov_pin = ENV.fetch('SIMPLECOV_VERSION', '')
gem 'simplecov', simplecov_pin unless simplecov_pin.empty?

# simplecov-cobertura's major line is coupled to simplecov's: 4.x requires
# simplecov ~> 1.0, so the 0.x compat cell can't use it and asks for 3.x via
# SIMPLECOV_COBERTURA_VERSION. Unset (the normal case) -> current 4.x.
cobertura_pin = ENV.fetch('SIMPLECOV_COBERTURA_VERSION', '')
cobertura_pin = '~> 4.0' if cobertura_pin.empty?
gem 'simplecov-cobertura', cobertura_pin

# Security auditing
gem 'bundler-audit', '~> 0.9', require: false
gem 'erb', '>= 6.0.4'
gem 'ruby_audit', '~> 3.1', require: false
