# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/scripts/pre_release_check'

RSpec.describe CovLoupe::Scripts::PreReleaseCheck do
  subject(:script) { described_class.new }

  describe '#call' do
    let(:root) { Pathname.new('/fake/root') }
    let(:version_file) { root.join('lib/cov_loupe/version.rb') }
    let(:release_notes) { root.join('RELEASE_NOTES.md') }
    let(:head_sha) { 'abc123def4567890' }
    let(:gem_sha256) { 'a' * 64 }
    let(:fake_gem) do
      gem_double = instance_double(Pathname, basename: 'cov-loupe-1.2.3.gem')
      allow(gem_double).to receive(:exist?).and_return(true)
      gem_double
    end
    let(:sha256_double) { instance_double(Digest::Base, hexdigest: gem_sha256) }

    before do
      # Speed up tests by not actually sleeping
      allow(Kernel).to receive(:sleep).with(any_args).and_return(nil)
      allow(script).to receive(:sleep) # rubocop:disable RSpec/SubjectStub

      # Mock the ROOT constant logic or Dir.chdir
      allow(Dir).to receive(:chdir).and_yield

      status_double = instance_double(Process::Status, success?: true)
      thread_double = instance_double(Thread, value: status_double)
      allow(Open3).to receive(:popen2e).and_yield(nil, [], thread_double)

      # Mock version file
      allow(described_class::ROOT).to receive(:join).and_call_original
      allow(described_class::ROOT).to receive(:join).with('lib/cov_loupe/version.rb')
        .and_return(version_file)
      allow(version_file).to receive(:read).and_return("module CovLoupe\n  VERSION = '1.2.3'\nend")

      # Mock Release Notes
      allow(described_class::ROOT).to receive(:join).with('RELEASE_NOTES.md')
        .and_return(release_notes)
      allow(release_notes).to receive(:read).and_return("## v1.2.3\n\n- Some changes")

      # Mock Gem build
      allow(FileUtils).to receive(:rm_f)
      allow(described_class::ROOT).to receive(:join).with('cov-loupe-1.2.3.gem')
        .and_return(fake_gem)
      allow(Digest::SHA256).to receive(:file).with(fake_gem).and_return(sha256_double)
    end

    # Helper to mock run! output for specific commands
    def mock_command(cmd, output)
      status_double = instance_double(Process::Status, success?: true)
      thread_double = instance_double(Thread, value: status_double)

      # Mock popen2e for streamed commands
      if cmd.is_a?(Array)
        allow(Open3).to receive(:popen2e).with(*cmd).and_yield(nil, [output], thread_double)
      else
        allow(Open3).to receive(:popen2e).with(cmd).and_yield(nil, [output], thread_double)
      end

      # Mock capture3 for captured commands
      if cmd.is_a?(Array)
        allow(Open3).to receive(:capture3).with(*cmd).and_return([output, '', status_double])
      else
        allow(Open3).to receive(:capture3).with(cmd).and_return([output, '', status_double])
      end
    end

    def mock_commands(command_outputs)
      command_outputs.each { |cmd, output| mock_command(cmd, output) }
    end

    def git_clean_commands(status: '')
      [[%w[git status --porcelain], status]]
    end

    def branch_commands(name)
      [[%w[git rev-parse --abbrev-ref HEAD], name]]
    end

    def sync_commands(local:, remote:, base: nil)
      commands = [
        [%w[git fetch origin --tags], ''],
        [%w[git rev-parse HEAD], local],
        [%w[git rev-parse origin/main], remote],
      ]
      commands << [%w[git merge-base HEAD origin/main], base] if base
      commands
    end

    def ci_list_command(head_sha)
      %w[gh run list --workflow test.yml --branch main --limit 100] +
        ['--commit', head_sha, '--json', described_class::CI_RUN_FIELDS]
    end

    def ci_commands(head_sha:, run_id: '999')
      runs_json = JSON.generate([
        { 'databaseId' => run_id, 'headSha' => head_sha, 'status' => 'completed',
          'conclusion' => 'success', 'event' => 'push' },
      ])

      [[ci_list_command(head_sha), runs_json]]
    end

    def mock_ci_run_lists(head_sha, *run_batches)
      status = instance_double(Process::Status, success?: true)
      results = run_batches.map { |runs| [JSON.generate(runs), '', status] }
      allow(Open3).to receive(:capture3).with(*ci_list_command(head_sha)).and_return(*results)
    end

    def tag_check_commands(tag = 'v1.2.3')
      [[['git', 'tag', '-l', tag], '']]
    end

    it 'runs through the checklist successfully' do
      mock_commands(
        git_clean_commands +
        branch_commands('main') +
        sync_commands(local: head_sha, remote: head_sha) +
        ci_commands(head_sha: head_sha) +
        tag_check_commands
      )
      mock_command(%w[gem build cov-loupe.gemspec], '')

      _result, out, _err = capture_io { script.call }
      aggregate_failures do
        expect(out).to include('✓ Gem built successfully')
        expect(out).to include("Built from commit: #{head_sha}")
        expect(out).to include("SHA256: #{gem_sha256}")
        expect(out).to include("git tag -a v1.2.3 -m 'Version 1.2.3' #{head_sha}")
        expect(out).to include('gem push cov-loupe-1.2.3.gem')
        expect(out).to include('is the authoritative artifact; do not rebuild it')
      end
    end

    it 'aborts if git is not clean' do
      mock_commands(git_clean_commands(status: 'M lib/foo.rb'))
      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end
      expect(err).to include('Uncommitted changes present. Commit or stash before releasing.')
    end

    it 'aborts if not on main branch' do
      mock_commands(git_clean_commands + branch_commands('feature-branch'))
      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end
      expect(err).to include('Releases must be cut from the main branch.')
    end

    it 'aborts if local is behind remote' do
      mock_commands(
        git_clean_commands +
        branch_commands('main') +
        sync_commands(local: 'sha1', remote: 'sha2', base: 'sha1') # base == local (behind)
      )

      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end
      expect(err).to include('Local main is behind origin. Pull before releasing.')
    end

    it 'aborts if local is ahead of remote' do
      mock_commands(
        git_clean_commands +
        branch_commands('main') +
        sync_commands(local: 'sha1', remote: 'sha2', base: 'sha2') # base == remote (ahead)
      )

      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end
      expect(err).to include('Local main is ahead of origin. Push before releasing.')
    end

    it 'aborts if local has diverged from remote' do
      mock_commands(
        git_clean_commands +
        branch_commands('main') +
        sync_commands(local: 'sha1', remote: 'sha2', base: 'sha3') # base != local and != remote (diverged)
      )

      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end
      expect(err).to include('Local main has diverged from origin. Reconcile before releasing.')
    end

    it 'aborts if release notes are missing' do
      mock_commands(
        git_clean_commands +
        branch_commands('main') +
        sync_commands(local: 'sha1', remote: 'sha1') +
        ci_commands(head_sha: 'sha1') +
        tag_check_commands
      )

      # Override release notes to not include the expected header
      allow(release_notes).to receive(:read).and_return("## v1.0.0\n\n- Old changes")

      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end
      expect(err).to include("Add a '## v1.2.3' section to RELEASE_NOTES.md before releasing.")
    end

    it 'warns when Unreleased notes still contain content' do
      mock_commands(
        git_clean_commands +
        branch_commands('main') +
        sync_commands(local: head_sha, remote: head_sha) +
        ci_commands(head_sha: head_sha) +
        tag_check_commands
      )
      mock_command(%w[gem build cov-loupe.gemspec], '')
      allow(release_notes).to receive(:read)
        .and_return("## v1.2.3\n\n- Release changes\n\n## Unreleased\n\n- Future change\n")

      _result, _out, err = capture_io { script.call }

      expect(err).to include("still has content under '## Unreleased'")
    end

    it 'checks the release heading before querying CI' do
      allow(Open3).to receive(:capture3).and_call_original
      mock_commands(git_clean_commands)
      allow(release_notes).to receive(:read).and_return("## Unreleased\n\n- Changes\n")

      _result, _out, err = capture_io do
        expect { script.call }.to raise_error(SystemExit)
      end

      expect(err).to include("Add a '## v1.2.3' section")
      expect(Open3).not_to have_received(:capture3).with(*ci_list_command(head_sha))
    end

    context 'when verifying CI' do
      def setup_release
        mock_commands(
          git_clean_commands +
          branch_commands('main') +
          sync_commands(local: head_sha, remote: head_sha) +
          tag_check_commands
        )
        mock_command(%w[gem build cov-loupe.gemspec], '')
      end

      def run_data(id:, sha: head_sha, status: 'completed', conclusion: 'success', event: 'push')
        { 'databaseId' => id, 'headSha' => sha, 'status' => status,
          'conclusion' => conclusion, 'event' => event }
      end

      it 'reuses a successful run for HEAD without dispatching or watching' do
        setup_release
        mock_ci_run_lists(head_sha, [
          run_data(id: 111, sha: 'wrongsha'),
          run_data(id: 123, conclusion: 'failure'),
          run_data(id: 456),
        ])

        _result, out, _err = capture_io { script.call }
        expect(out).to include('Using successful CI run 456')
        expect(Open3).not_to have_received(:popen2e).with(*%w[gh workflow run test.yml --ref main])
        expect(Open3).not_to have_received(:popen2e).with('gh', 'run', 'watch', anything, '--exit-status')
      end

      it 'watches an existing run for HEAD while it is in progress' do
        setup_release
        mock_ci_run_lists(head_sha, [run_data(id: 123, status: 'in_progress', conclusion: nil)])
        mock_command(%w[gh run watch 123 --exit-status], '')

        expect { suppress_io { script.call } }.not_to raise_error
        expect(Open3).to have_received(:popen2e).with(*%w[gh run watch 123 --exit-status])
        expect(Open3).not_to have_received(:popen2e).with(*%w[gh workflow run test.yml --ref main])
      end

      it 'dispatches and watches a new run when no successful run exists' do
        setup_release
        old_run = run_data(id: 111, conclusion: 'failure', event: 'workflow_dispatch')
        new_run = run_data(id: 222, status: 'queued', conclusion: nil, event: 'workflow_dispatch')
        mock_ci_run_lists(head_sha, [old_run], [old_run], [new_run, old_run])
        mock_command(%w[gh workflow run test.yml --ref main], '')
        mock_command(%w[gh run watch 222 --exit-status], '')

        _result, out, _err = capture_io { script.call }
        expect(out).to include('CI run 111 failed', 'gh run view 111 --log-failed')
        expect(Open3).to have_received(:popen2e).with(*%w[gh workflow run test.yml --ref main])
        expect(Open3).to have_received(:popen2e).with(*%w[gh run watch 222 --exit-status])
      end

      it 'forces a fresh run with --rerun-ci even when HEAD already passed' do
        forced_script = described_class.new(rerun_ci: true)
        setup_release
        old_run = run_data(id: 111)
        new_run = run_data(id: 222, event: 'workflow_dispatch')
        mock_ci_run_lists(head_sha, [old_run], [new_run, old_run])
        mock_command(%w[gh workflow run test.yml --ref main], '')
        mock_command(%w[gh run watch 222 --exit-status], '')

        _result, out, _err = capture_io { forced_script.call }
        expect(out).to include('Starting a fresh CI run (--rerun-ci)')
        expect(Open3).to have_received(:popen2e).with(*%w[gh workflow run test.yml --ref main])
        expect(Open3).to have_received(:popen2e).with(*%w[gh run watch 222 --exit-status])
      end

      it 'ignores unrelated new runs while finding the dispatched run' do
        setup_release
        wrong_sha = run_data(id: 111, sha: 'wrongsha', event: 'workflow_dispatch')
        push_run = run_data(id: 222, event: 'push')
        new_run = run_data(id: 333, event: 'workflow_dispatch')
        mock_ci_run_lists(head_sha, [], [wrong_sha, push_run, new_run])
        mock_command(%w[gh workflow run test.yml --ref main], '')
        mock_command(%w[gh run watch 333 --exit-status], '')

        expect { suppress_io { script.call } }.not_to raise_error
        expect(Open3).to have_received(:popen2e).with(*%w[gh run watch 333 --exit-status])
      end

      it 'times out if no dispatched run appears' do
        setup_release
        mock_ci_run_lists(head_sha, [], [])
        mock_command(%w[gh workflow run test.yml --ref main], '')
        stub_const('CovLoupe::Scripts::PreReleaseCheck::CI_POLL_ATTEMPTS', 1)

        _result, _out, err = capture_io do
          expect { script.call }.to raise_error(SystemExit)
        end
        expect(err).to include("Timed out waiting for workflow run to appear for HEAD SHA #{head_sha}")
      end

      it 'reports invalid JSON from GitHub' do
        setup_release
        mock_command(ci_list_command(head_sha), 'invalid json{')

        _result, _out, err = capture_io do
          expect { script.call }.to raise_error(SystemExit)
        end
        expect(err).to include('Failed to parse GitHub API response')
      end
    end
  end

  describe 'command-line options' do
    it 'prints a concise error for an unknown option' do
      executable = described_class::ROOT.join('bin/pre-release-check').to_s
      _out, err, status = Open3.capture3(RbConfig.ruby, executable, '--bogus')

      expect(status.exitstatus).to eq(1)
      expect(err).to include('invalid option: --bogus', 'Usage: bin/pre-release-check [--rerun-ci]')
      expect(err).not_to include('bin/pre-release-check:')
    end
  end
end
