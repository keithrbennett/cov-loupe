# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

RSpec.describe 'dev/scripts/verify_doc_links.rb' do
  let(:script) { File.expand_path('../../../dev/scripts/verify_doc_links.rb', __dir__) }

  # A git repository whose gem packages README.md and docs/user/, but not docs/dev/ or notes.md.
  def run_in_repo(files)
    Dir.mktmpdir do |dir|
      files = {
        'demo.gemspec' => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = 'demo'
            spec.version = '1.0.0'
            spec.summary = 'demo'
            spec.authors = ['demo']
            spec.files = `git ls-files -z`.split("\\x0").select do |f|
              f == 'README.md' || f.start_with?('docs/user/')
            end
          end
        RUBY
      }.merge(files)
      files.each do |path, content|
        FileUtils.mkdir_p(File.join(dir, File.dirname(path)))
        File.write(File.join(dir, path), content)
      end
      system('git', 'init', '-q', dir, exception: true)
      system('git', '-C', dir, 'add', '.', exception: true)

      output, status = Open3.capture2e(RbConfig.ruby, script, '--no-server', '--root', dir)
      yield output, status
    end
  end

  [
    ['a packaged page links to a packaged page', 'docs/user/guide.md', true],
    ['a packaged page links to a packaged directory', 'docs/user/', true],
    ['a packaged page links to an unpackaged page', 'docs/dev/notes.md', false],
  ].each do |description, target, valid|
    it "#{valid ? 'accepts' : 'reports'} a link when #{description}" do
      files = {
        'README.md'          => "[link](#{target})\n",
        'docs/user/guide.md' => "# Guide\n",
        'docs/dev/notes.md'  => "# Notes\n",
      }
      run_in_repo(files) do |output, status|
        expect(status.success?).to eq(valid), output
        expect(output).to include('docs/dev/notes.md is not packaged in the gem') unless valid
      end
    end
  end

  it 'allows an unpackaged page to link to another unpackaged page' do
    files = { 'notes.md' => "[link](docs/dev/notes.md)\n", 'docs/dev/notes.md' => "# Notes\n" }
    run_in_repo(files) do |output, status|
      expect(status.success?).to be(true), output
    end
  end
end
