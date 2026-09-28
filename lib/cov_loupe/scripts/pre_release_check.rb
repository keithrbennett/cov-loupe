# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'pathname'
require_relative 'command_execution'
require_relative 'release_metadata'

module CovLoupe
  module Scripts
    class PreReleaseCheck
      include CommandExecution

      ROOT = Pathname.new(__dir__).join('../../..').expand_path
      CI_RUN_FIELDS = 'databaseId,headSha,status,conclusion,event'
      CI_POLL_ATTEMPTS = 100
      CI_POLL_INTERVAL = 3

      def initialize(rerun_ci: false)
        @rerun_ci = rerun_ci
      end

      def call
        Dir.chdir(ROOT) do
          verify_git_clean!
          puts '✓ Git working tree is clean'

          @version = fetch_version
          @tag_name = "v#{@version}"
          puts "✓ Preparing release for version #{@version}"

          verify_release_notes!
          warn_about_unreleased_content!

          verify_branch!
          puts '✓ On main branch'

          verify_sync!
          puts '✓ Local branch is in sync with origin/main'

          verify_ci_passed!
          puts '✓ GitHub Actions CI passed'

          puts "✓ Release notes found for #{@tag_name}"

          verify_tag_new!
          puts "✓ Tag #{@tag_name} does not yet exist"

          build_gem!
          puts '✓ Gem built successfully'

          puts "\nBuild complete! #{@gem_file.basename} is the authoritative artifact; do not rebuild it."
          puts
          puts "  Built from commit: #{@head_sha}"
          puts "  SHA256: #{@gem_sha256}"
          puts
          puts 'To finish the release, run:'
          puts
          puts "  git tag -a #{@tag_name} -m 'Version #{@version}' #{@head_sha}"
          puts '  git push origin main --follow-tags'
          puts "  gem push #{@gem_file.basename}"
          puts
          puts 'Then draft the GitHub release via the web UI.'
        end
      end

      private def verify_git_clean!
        status = run_command(%w[git status --porcelain], print_output: false)
        unless status.strip.empty?
          abort_with('Uncommitted changes present. Commit or stash before releasing.')
        end
      end

      private def verify_branch!
        current_branch = run_command(%w[git rev-parse --abbrev-ref HEAD], print_output: false).strip
        abort_with('Releases must be cut from the main branch.') unless current_branch == 'main'
      end

      private def verify_sync!
        run_command(%w[git fetch origin --tags], print_output: true)
        @head_sha = run_command(%w[git rev-parse HEAD], print_output: false).strip
        remote = run_command(%w[git rev-parse origin/main], print_output: false).strip
        return if @head_sha == remote

        base = run_command(%w[git merge-base HEAD origin/main], print_output: false).strip

        if base == @head_sha
          abort_with('Local main is behind origin. Pull before releasing.')
        elsif base == remote
          abort_with('Local main is ahead of origin. Push before releasing.')
        else
          abort_with('Local main has diverged from origin. Reconcile before releasing.')
        end
      end

      private def verify_ci_passed!
        head_sha = run_command(%w[git rev-parse HEAD], print_output: false).strip
        runs = ci_runs(head_sha)

        unless @rerun_ci
          successful_run = runs.find do |run|
            run['status'] == 'completed' && run['conclusion'] == 'success'
          end
          if successful_run
            puts "Using successful CI run #{successful_run['databaseId']} for HEAD SHA #{head_sha}."
            return
          end

          running_run = runs.find { |run| run['status'] != 'completed' }
          if running_run
            watch_ci_run(running_run['databaseId'])
            return
          end
        end

        existing_run_ids = runs.map { |run| run['databaseId'] }
        puts 'Starting a fresh CI run (--rerun-ci); ignoring existing runs for HEAD.' if @rerun_ci
        run_command(%w[gh workflow run test.yml --ref main], print_output: true)
        puts 'Waiting for workflow to initialize...'

        run_id = find_triggered_run_id(head_sha, existing_run_ids)
        watch_ci_run(run_id)
      end

      private def watch_ci_run(run_id)
        puts "Monitoring CI build (Run ID: #{run_id})..."
        run_command(['gh', 'run', 'watch', run_id.to_s, '--exit-status'], print_output: true)
      end

      private def find_triggered_run_id(head_sha, existing_run_ids)
        CI_POLL_ATTEMPTS.times do |attempt|
          runs = ci_runs(head_sha)
          matching_run = runs.find do |run|
            run['event'] == 'workflow_dispatch' && !existing_run_ids.include?(run['databaseId'])
          end
          return matching_run['databaseId'] if matching_run

          sleep CI_POLL_INTERVAL if attempt < CI_POLL_ATTEMPTS - 1
        end

        abort_with("Timed out waiting for workflow run to appear for HEAD SHA #{head_sha}")
      end

      private def ci_runs(head_sha)
        runs_json = run_command(
          %w[gh run list --workflow test.yml --branch main --limit 100] +
            ['--commit', head_sha, '--json', CI_RUN_FIELDS],
          print_output: false
        )
        return [] if runs_json.empty?

        JSON.parse(runs_json).select { |run| run['headSha'] == head_sha }
      rescue JSON::ParserError => e
        abort_with("Failed to parse GitHub API response: #{e.message}")
      end

      private def fetch_version
        version_file = ROOT.join('lib/cov_loupe/version.rb')
        version_source = version_file.read
        version = ReleaseMetadata.version_from(version_source)
        abort_with("Could not find exactly one VERSION constant in #{version_file}") unless version
        abort_with("Invalid release version in #{version_file}: #{version}") unless
          ReleaseMetadata.valid_version?(version)
        version
      end

      private def verify_release_notes!
        release_notes = ROOT.join('RELEASE_NOTES.md').read
        unless ReleaseMetadata.release_heading?(release_notes, @version)
          abort_with("Add a '## #{@tag_name}' section to RELEASE_NOTES.md before releasing.")
        end
      end

      private def warn_about_unreleased_content!
        release_notes = ROOT.join('RELEASE_NOTES.md').read
        return unless ReleaseMetadata.unreleased_content?(release_notes)

        warn("WARNING: RELEASE_NOTES.md still has content under '## Unreleased'; " \
             "review whether it belongs in #{@tag_name}.")
      end

      private def verify_tag_new!
        existing_tag = run_command(['git', 'tag', '-l', @tag_name], print_output: false)
          .split("\n").include?(@tag_name)
        abort_with("Tag #{@tag_name} already exists. Bump the version before releasing.") if existing_tag
      end

      private def build_gem!
        @gem_file = ROOT.join("cov-loupe-#{@version}.gem")
        FileUtils.rm_f(@gem_file)
        run_command(%w[gem build cov-loupe.gemspec], print_output: true)
        abort_with("Gem file #{@gem_file} not found after build.") unless @gem_file.exist?
        @gem_sha256 = Digest::SHA256.file(@gem_file).hexdigest
      end
    end
  end
end
