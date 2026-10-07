# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Checks the executable bit as committed in git rather than via File.executable?,
# which is unreliable on Windows.
RSpec.describe 'tracked git hooks' do
  let(:repo_root) { File.expand_path('../../..', __dir__) }
  let(:hook_modes) do
    out, status = begin
      Open3.capture2('git', 'ls-files', '-s', 'hooks', chdir: repo_root)
    rescue Errno::ENOENT
      skip 'git not available'
    end
    skip 'not a git checkout' unless status.success?
    out.lines.to_h do |line|
      mode, _sha, _stage, path = line.split(/\s+/, 4)
      [File.basename(path.strip), mode]
    end
  end

  %w[pre-commit pre-merge-commit].each do |name|
    it "tracks #{name} as an executable hook" do
      expect(hook_modes[name]).to eq('100755')
    end
  end

  it 'tracks every hook as executable' do
    expect(hook_modes.reject { |_name, mode| mode == '100755' }).to be_empty
  end
end
