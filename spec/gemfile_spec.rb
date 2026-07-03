# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gemfile dependencies' do
  def gemfile_dependencies_for(ruby_engine:, ruby_version:)
    require 'json'
    require 'open3'
    require 'rbconfig'

    ruby_source = <<~RUBY
      require 'json'
      require 'bundler/dsl'

      dsl = Bundler::Dsl.new
      gemfile_path = #{File.expand_path('../Gemfile', __dir__).inspect}
      gemfile_source = File.read(gemfile_path)
        .gsub(/\\bRUBY_ENGINE\\b/, #{ruby_engine.inspect.inspect})
        .gsub(/\\bRUBY_VERSION\\b/, #{ruby_version.inspect.inspect})
      dsl.instance_eval(gemfile_source, gemfile_path)
      puts dsl.dependencies.map(&:name).sort.to_json
    RUBY

    stdout_str, stderr_str, status = Open3.capture3(RbConfig.ruby, '-e', ruby_source)
    expect(status).to be_success, stderr_str

    JSON.parse(stdout_str)
  end

  it 'does not add irb or rdoc for jruby' do
    dependencies = gemfile_dependencies_for(ruby_engine: 'jruby', ruby_version: '3.4.0')

    expect(dependencies).not_to include('irb', 'rdoc')
  end

  it 'adds irb and rdoc for Ruby 3.4+' do
    dependencies = gemfile_dependencies_for(ruby_engine: 'ruby', ruby_version: '3.4.0')

    expect(dependencies).to include('irb', 'rdoc')
  end
end
