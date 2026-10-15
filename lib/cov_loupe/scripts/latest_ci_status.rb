# frozen_string_literal: true

require 'json'
require_relative 'command_execution'

module CovLoupe
  module Scripts
    # @api private
    class LatestCiStatus
      include CommandExecution

      def call
        branch = fetch_current_branch
        puts "Fetching latest CI run for branch: #{branch}..."

        run_data = fetch_latest_run(branch)

        if run_data.nil?
          puts "No workflow runs found for branch '#{branch}'."
          return
        end

        display_run_details(run_data)
      end

      private def fetch_current_branch
        run_command(%w[git rev-parse --abbrev-ref HEAD])
      end

      private def fetch_latest_run(branch)
        json_output, success = run_command_with_status(
          ['gh', 'run', 'list', '--branch', branch, '--limit', '1', '--json',
            'databaseId,status,conclusion,url,displayTitle,createdAt']
        )

        unless success
          warn "Failed to fetch runs. Ensure 'gh' is installed and you are authenticated."
          exit 1
        end

        runs = JSON.parse(json_output)
        runs.first
      end

      private def display_run_details(run)
        id = run['databaseId']
        status = run['status']
        conclusion = run['conclusion']
        url = run['url']
        title = run['displayTitle']
        created_at = run['createdAt']

        color = status_color(status, conclusion)
        display_status = status == 'completed' ? (conclusion || 'unknown').upcase : status.upcase

        puts "\nLatest Run Details:"
        puts '-------------------'
        puts "Title:      #{title}"
        puts "ID:         #{id}"
        puts "Time:       #{created_at}"
        puts "Status:     #{colorize(display_status, color)}"
        puts "URL:        #{url}"

        handle_status_action(status, conclusion, id)
      end

      private def handle_status_action(status, conclusion, id)
        if status == 'completed' && %w[failure startup_failure timed_out].include?(conclusion)
          puts "\n#{colorize('Fetching failure logs...', 31)}"
          puts '------------------------'
          system('gh', 'run', 'view', id.to_s, '--log-failed')
        elsif status == 'in_progress'
          puts "\n#{colorize('Build is currently running... ⏳', 34)}"
          puts "You can watch it with: gh run watch #{id}"
        elsif status == 'queued'
          puts "\n#{colorize('Build is queued... 🕒', 34)}"
        end
      end

      private def colorize(text, color_code)
        "\e[#{color_code}m#{text}\e[0m"
      end

      private def status_color(status, conclusion)
        if status == 'completed'
          case conclusion
          when 'success' then 32 # Green
          when 'failure', 'startup_failure', 'timed_out' then 31 # Red
          when 'cancelled' then 33 # Yellow
          else 37 # White
          end
        else
          34 # Blue for in_progress/queued
        end
      end
    end
  end
end
