# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Development dependencies
gem 'rake'
gem 'rspec', '~> 3.0'
gem 'rubocop', '~> 1.87.0'
gem 'rubocop-rspec', '~> 3.9.0'
gem 'simplecov-cobertura'

# Security auditing
gem 'bundler-audit', require: false
gem 'ruby_audit', require: false

# Ruby 3.5+ will remove irb and rdoc from default gems
gem 'irb', '>= 1.0' if RUBY_VERSION >= '3.4'
gem 'rdoc', '>= 6.0' if RUBY_VERSION >= '3.4'
