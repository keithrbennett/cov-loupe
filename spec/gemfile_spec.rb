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
      Object.send(:remove_const, :RUBY_ENGINE)
      Object.const_set(:RUBY_ENGINE, #{ruby_engine.inspect})
      Object.send(:remove_const, :RUBY_VERSION)
      Object.const_set(:RUBY_VERSION, #{ruby_version.inspect})

      dsl = Bundler::Dsl.new
      dsl.eval_gemfile(#{File.expand_path('../Gemfile', __dir__).inspect})
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
