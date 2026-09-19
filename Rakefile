# frozen_string_literal: true

begin
  require 'bundler/setup'
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  task :spec do
    abort 'RSpec is not installed. Add it to your bundle and run `bundle install`.'
  end
  task default: :spec
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
rescue LoadError
  task :rubocop do
    abort 'RuboCop is not installed. Add it to your bundle and run `bundle install`.'
  end
end

namespace :security do
  desc 'Audit dependencies for vulnerabilities with bundler-audit'
  task :bundler_audit do
    sh 'bundle exec bundle audit check --update'
  end

  desc 'Audit Ruby and RubyGems for known vulnerabilities with ruby_audit'
  task :ruby_audit do
    sh 'bundle exec ruby-audit'
  end

  desc 'Audit locked Python docs dependencies for vulnerabilities with pip-audit'
  task :pip_audit do
    sh 'bin/audit-docs-deps'
  end

  desc 'Run all security audits'
  task :all do
    failures = []

    begin
      Rake::Task['security:bundler_audit'].invoke
    rescue => e
      failures << "bundler-audit failed: #{e.message}"
    end

    begin
      Rake::Task['security:ruby_audit'].invoke
    rescue => e
      failures << "ruby-audit failed: #{e.message}"
    end

    begin
      Rake::Task['security:pip_audit'].invoke
    rescue => e
      failures << "pip-audit failed: #{e.message}"
    end

    if failures.empty?
      puts '--- Security audits completed successfully ---'
      next
    end

    failures.each { |message| warn message }
    abort 'Security audits failed'
  end
end

desc 'Run all security audits'
task security: 'security:all'

require_relative 'lib/cov_loupe/scripts/pre_release_check'
require_relative 'lib/cov_loupe/scripts/latest_ci_status'
require_relative 'lib/cov_loupe/scripts/setup_doc_server'
require_relative 'lib/cov_loupe/scripts/start_doc_server'

namespace :release do
  desc 'Run pre-release checks (git status, CI, version bump)'
  task :check do
    CovLoupe::Scripts::PreReleaseCheck.new.call
  end
end

namespace :ci do
  desc 'Get latest CI status'
  task :status do
    CovLoupe::Scripts::LatestCiStatus.new.call
  end
end

desc 'Get latest CI status'
task ci: 'ci:status'

namespace :docs do
  desc 'Build documentation with mkdocs'
  task :build do
    sh 'bin/build-docs'
  end

  desc 'Build and deploy documentation with mkdocs'
  task :deploy do
    sh 'bin/deploy-docs'
  end

  desc 'Set up python environment for docs'
  task :setup do
    CovLoupe::Scripts::SetupDocServer.new.call
  end

  desc 'Start documentation server'
  task :serve do
    CovLoupe::Scripts::StartDocServer.new.call
  end
end

desc 'Build documentation with mkdocs; `rake docs` defaults to build'
task docs: 'docs:build'

desc 'Run full test suite (rubocop + rspec + docs build)'
task test: %i[rubocop spec docs:build]
