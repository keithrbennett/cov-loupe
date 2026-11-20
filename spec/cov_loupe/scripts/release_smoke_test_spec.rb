# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'cov_loupe/scripts/release_smoke_test'

RSpec.describe CovLoupe::Scripts::ReleaseSmokeTest do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:gem_file) { root.join('cov-loupe-7.1.0.gem') }
  let(:success) { instance_double(Process::Status, success?: true) }
  let(:failure) { instance_double(Process::Status, success?: false) }
  let(:gem_version) { '7.1.0' }
  let(:dependencies) { [] }
  let(:install_ok) { true }
  # Output of the installed executable, by its first argument; nil makes the command fail.
  # :readme is the README path in the temporary gem directory the command runs in, created there;
  # :unpackaged_readme is that path, not created.
  let(:outputs) do
    { '--version' => '7.1.0', '--help' => 'Usage: cov-loupe', '--path-for' => :readme,
      'totals' => totals_json(7, 7), '-m' => '{"jsonrpc":"2.0","id":1,"result":{"content":[]}}' }
  end
  let(:calls) { [] }

  def totals_json(total, fresh)
    JSON.generate('file_counts' => { 'total' => total, 'with_coverage' => { 'ok' => fresh } })
  end

  # A successful install creates the installed gem's directory.
  def install_result(chdir)
    return ['', 'missing dependency', failure] unless install_ok

    FileUtils.mkdir_p(File.join(chdir, "gems/cov-loupe-#{gem_version}"))
    ['', '', success]
  end

  def stub_gem(version)
    spec = instance_double(Gem::Specification, version: Gem::Version.new(version),
      full_name: "cov-loupe-#{version}", runtime_dependencies: dependencies)
    allow(Gem::Package).to receive(:new).and_return(instance_double(Gem::Package, spec: spec))
  end

  def run_smoke_test(*args)
    result, out, err = capture_io(swallow_exit: true) { described_class.new(*args).call }
    [result.is_a?(SystemExit) ? result.status : 0, out, err]
  end

  before do
    stub_const('CovLoupe::Scripts::ReleaseSmokeTest::ROOT', root)
    FileUtils.mkdir_p(root.join('lib/cov_loupe'))
    root.join('lib/cov_loupe/version.rb').write("VERSION = '7.1.0'\n")
    gem_file.write('')
    stub_gem(gem_version)

    allow(Open3).to receive(:capture3) do |env, *cmd, chdir:, stdin_data:|
      calls << { env: env, cmd: cmd, chdir: chdir, stdin_data: stdin_data }
      next install_result(chdir) if cmd.include?('install')

      out = outputs.fetch(cmd[2])
      if %i[readme unpackaged_readme].include?(out)
        packaged = out == :readme
        out = File.join(chdir, 'gems/cov-loupe-7.1.0/README.md')
        FileUtils.mkdir_p(File.dirname(out))
        File.write(out, '') if packaged
      end
      out.nil? ? ['', 'boom', failure] : ["#{out}\n", '', success]
    end
  end

  after { FileUtils.remove_entry(root) }

  it 'installs the gem without network access, isolated, and passes when every check does' do
    status, out, _err = run_smoke_test

    expect(status).to eq(0)
    expect(out).to include('✓ --version prints the version', '✓ MCP server answers a help call',
      'Smoke test passed for cov-loupe-7.1.0.gem.')
    install = calls.first
    expect(install[:cmd].drop(1)).to eq(['install', '--local', '--no-document', '--ignore-dependencies',
      '--install-dir', install[:chdir], gem_file.to_s])
    calls.each do |call|
      expect(call[:env]).to include('GEM_HOME' => call[:chdir], 'COV_LOUPE_OPTS' => nil)
      expect(call[:env]['GEM_PATH']).to eq(call[:chdir])
    end
  end

  it 'uses the resolved temporary directory, as the installed gem reports resolved paths' do
    skip 'creating symlinks needs extra privileges on Windows' if Gem.win_platform?

    Dir.mktmpdir do |dir|
      real = File.join(dir, 'real')
      link = File.join(dir, 'link')
      FileUtils.mkdir(real)
      File.symlink(real, link)
      allow(Dir).to receive(:mktmpdir).and_yield(link)

      expect(run_smoke_test.first).to eq(0)
      expect(calls.map { |call| call[:chdir] }.uniq).to eq([File.realpath(real)])
    end
  end

  it 'sends a JSON-RPC help call to the MCP server' do
    run_smoke_test
    mcp = calls.find { |call| call[:cmd].include?('mcp') }
    expect(mcp[:stdin_data]).to include('"name":"help"')
  end

  [
    ['--version', '7.0.0', '--version prints the version'],
    ['--help', 'no usage here', '--help prints usage'],
    ['--help', nil, '--help prints usage'],
    ['--path-for', "#{Dir.pwd}/README.md", 'runs from the installed gem, with its README'],
    ['totals', 'not json', 'totals reads coverage data'],
    ['totals', '{}', 'totals reads coverage data'],
    ['totals', '[1]', 'totals reads coverage data'],
    ['totals', '{"file_counts":{"total":7,"with_coverage":{"ok":6}}}', 'totals reads coverage data'],
    ['totals', '{"file_counts":{"total":0,"with_coverage":{"ok":0}}}', 'totals reads coverage data'],
    ['totals', '{"file_counts":{"total":8,"with_coverage":{"ok":7},"without_coverage":{"total":1}}}',
      'totals reads coverage data'],
    ['-m', '"text"', 'MCP server answers a help call'],
    ['-m', '{"jsonrpc":"2.0","id":1,"result":{"isError":true}}', 'MCP server answers a help call'],
    ['-m', nil, 'MCP server answers a help call'],
    ['-m', 'not json', 'MCP server answers a help call'],
  ].each do |arg, output, check|
    it "fails when '#{check}' gets #{output.inspect}" do
      outputs[arg] = output
      status, out, err = run_smoke_test

      expect(status).to eq(1)
      expect(out).to include("✗ #{check}")
      expect(err).to include('1 smoke test check(s) failed')
    end
  end

  it 'fails when the README path is in the gem but the file is not packaged' do
    outputs['--path-for'] = :unpackaged_readme
    status, out, _err = run_smoke_test

    expect(status).to eq(1)
    expect(out).to include('README is missing from the gem')
  end

  context 'with a gem whose version differs from the checkout' do
    let(:gem_version) { '7.2.0' }

    it 'expects the version the gem declares' do
      outputs['--version'] = '7.2.0'
      expect(run_smoke_test.first).to eq(0)
    end
  end

  it 'runs totals against the demo project the installed gem ships' do
    run_smoke_test
    totals = calls.find { |call| call[:cmd][2] == 'totals' }
    expect(totals[:cmd].last).to eq(File.join(totals[:chdir],
      'gems/cov-loupe-7.1.0/docs/fixtures/demo_project'))
  end

  describe 'dependencies' do
    let(:installed) { Pathname.new(Dir.mktmpdir) }
    let(:dep_spec) do
      gem_dir = installed.join('gems/dep-1.0')
      ext_dir = installed.join('extensions/x86_64-linux/4.0.0/dep-1.0')
      spec_file = installed.join('specifications/dep-1.0.gemspec')
      [gem_dir, ext_dir, spec_file.dirname].each { |dir| FileUtils.mkdir_p(dir) }
      gem_dir.join('dep.rb').write('')
      ext_dir.join('dep.so').write('')
      spec_file.write('')
      instance_double(Gem::Specification, full_name: 'dep-1.0', default_gem?: false, runtime_dependencies: [],
        base_dir: installed.to_s, full_gem_path: gem_dir.to_s, extension_dir: ext_dir.to_s,
        loaded_from: spec_file.to_s)
    end
    let(:dependencies) { [instance_double(Gem::Dependency, to_spec: dep_spec)] }
    let(:staged) { [] }

    before do
      # Record what the temporary gem directory holds when the gem is installed into it.
      allow(Open3).to receive(:capture3).and_wrap_original do |_original, _env, *cmd, chdir:, **|
        next ['', '', failure] unless cmd.include?('install')

        staged.replace(Dir.glob('**/*', base: chdir).sort)
        install_result(chdir)
      end
    end

    after { FileUtils.remove_entry(installed) }

    it "copies each dependency's files, extensions and specification before installing" do
      run_smoke_test
      expect(staged).to include('gems/dep-1.0/dep.rb', 'extensions/x86_64-linux/4.0.0/dep-1.0/dep.so',
        'specifications/dep-1.0.gemspec')
    end

    it 'copies a dependency without compiled extensions' do
      FileUtils.rm_rf(dep_spec.extension_dir)
      run_smoke_test
      expect(staged).to include('gems/dep-1.0/dep.rb')
      expect(staged.grep(/extensions/)).to be_empty
    end

    it 'leaves out default gems, which Ruby provides' do
      allow(dep_spec).to receive(:default_gem?).and_return(true)
      run_smoke_test
      expect(staged.grep(/dep-1.0/)).to be_empty
    end

    it 'aborts when a declared dependency is not installed' do
      allow(dependencies.first).to receive(:to_spec).and_raise(Gem::MissingSpecError.new('dep', '>= 0'))
      status, _out, err = run_smoke_test
      expect(status).to eq(1)
      expect(err).to include('A runtime dependency is not installed at a version the gem accepts')
    end
  end

  [Gem::Package::FormatError.new('bad'), ArgumentError.new('invalid byte sequence')].each do |error|
    it "aborts when the file is not a valid gem (#{error.class})" do
      allow(Gem::Package).to receive(:new).and_raise(error)
      status, _out, err = run_smoke_test
      expect(status).to eq(1)
      expect(err).to include('is not a valid gem')
    end
  end

  it 'aborts when the install leaves no installed gem directory' do
    allow(self).to receive(:install_result).and_return(['', '', success])
    status, _out, err = run_smoke_test
    expect(status).to eq(1)
    expect(err).to include('was not installed in')
  end

  it 'aborts with the output when the install fails' do
    allow(self).to receive(:install_ok).and_return(false)
    status, _out, err = run_smoke_test
    expect(status).to eq(1)
    expect(err).to include('Could not install cov-loupe-7.1.0.gem', 'missing dependency')
  end

  it 'reports a command that cannot be run instead of raising' do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'gem')
    status, _out, err = run_smoke_test
    expect(status).to eq(1)
    expect(err).to include('could not run')
  end

  it 'uses the gem rake build wrote to pkg/ when the root has none' do
    gem_file.delete
    pkg_gem = root.join('pkg/cov-loupe-7.1.0.gem')
    FileUtils.mkdir_p(pkg_gem.dirname)
    pkg_gem.write('')
    run_smoke_test
    expect(calls.first[:cmd]).to include(pkg_gem.to_s)
  end

  it 'aborts, naming the places it looked, when there is no gem file' do
    gem_file.delete
    status, _out, err = run_smoke_test
    expect(status).to eq(1)
    expect(err).to include('cov-loupe-7.1.0.gem not found in the repository root or pkg/')
  end

  it 'uses a gem file given as an argument, and rejects a directory' do
    other = root.join('other.gem')
    other.write('')
    run_smoke_test(other.to_s)
    expect(calls.first[:cmd]).to include(other.to_s)

    status, _out, err = run_smoke_test(root.to_s)
    expect(status).to eq(1)
    expect(err).to include('is not a gem file')

    status, _out, err = run_smoke_test(root.join('missing.gem').to_s)
    expect(status).to eq(1)
    expect(err).to include('missing.gem does not exist')
  end
end
