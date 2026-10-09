# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/paths/glob_utils'

RSpec.describe CovLoupe::GlobUtils do
  before do
    described_class.instance_variable_set(:@fn_normalize_path_separators, nil)
    CovLoupe::VolumeCaseSensitivity.clear_cache
  end

  describe '.normalize_patterns' do
    it 'converts patterns to strings' do
      expect(described_class.normalize_patterns([123])).to eq(['123'])
    end

    it 'removes nil patterns' do
      expect(described_class.normalize_patterns(['a', nil, 'b'])).to eq(%w[a b])
    end

    it 'removes empty patterns' do
      expect(described_class.normalize_patterns(['a', '', 'b'])).to eq(%w[a b])
    end

    it 'handles single string input' do
      expect(described_class.normalize_patterns('foo')).to eq(['foo'])
    end

    it 'handles nil input' do
      expect(described_class.normalize_patterns(nil)).to eq([])
    end
  end

  describe '.fn_normalize_path_separators' do
    it 'normalizes backslashes when running on Windows' do
      allow(CovLoupe).to receive(:windows?).and_return(true)

      normalizer = described_class.fn_normalize_path_separators
      expect(normalizer.call('C:\\tmp\\file.rb')).to eq('C:/tmp/file.rb')
    end

    it 'returns paths unchanged when not running on Windows' do
      allow(CovLoupe).to receive(:windows?).and_return(false)

      normalizer = described_class.fn_normalize_path_separators
      expect(normalizer.call('/tmp/file.rb')).to eq('/tmp/file.rb')
      expect(normalizer.call('lib/foo.rb')).to eq('lib/foo.rb')
    end
  end

  describe '.absolutize_pattern' do
    let(:pattern_start) { Gem.win_platform? ? /\A[a-zA-Z]:/ : /\A/ }

    it 'returns absolute path for a relative pattern' do
      expect(described_class.absolutize_pattern('lib/*.rb', '/root'))
        .to match(%r{#{pattern_start}/root/lib/\*\.rb\z})
    end

    it 'returns the pattern itself if it is already absolute' do
      expect(described_class.absolutize_pattern('/tmp/*.rb', '/root'))
        .to match(%r{#{pattern_start}/tmp/\*\.rb\z})
    end
  end

  describe '.matches_any_pattern?' do
    it 'returns true if path matches one of the patterns' do
      patterns = ['/root/lib/*.rb', '/root/spec/*.rb']
      expect(described_class.matches_any_pattern?('/root/lib/foo.rb', patterns)).to be true
    end

    it 'returns false if path does not match any pattern' do
      patterns = ['/root/lib/*.rb']
      expect(described_class.matches_any_pattern?('/root/spec/foo_spec.rb', patterns)).to be false
    end

    it 'supports extglob' do
      # Example: matches either .rb or .erb
      patterns = ['/root/lib/*.{rb,erb}']
      expect(described_class.matches_any_pattern?('/root/lib/view.erb', patterns)).to be true
    end

    it 'supports recursive matching (**)' do
      patterns = ['/root/**/*.rb']
      expect(described_class.matches_any_pattern?('/root/lib/deeply/nested/file.rb',
        patterns)).to be true
    end

    it 'respects directory boundaries with * (does not cross directories)' do
      patterns = ['/root/lib/*.rb']
      expect(described_class.matches_any_pattern?('/root/lib/subdir/file.rb', patterns)).to be false
    end

    it 'supports character sets ([...])' do
      patterns = ['/root/file[1-9].rb']
      expect(described_class.matches_any_pattern?('/root/file5.rb', patterns)).to be true
      expect(described_class.matches_any_pattern?('/root/fileA.rb', patterns)).to be false
    end

    it 'supports single character wildcard (?)' do
      patterns = ['/root/test?.rb']
      expect(described_class.matches_any_pattern?('/root/test1.rb', patterns)).to be true
      expect(described_class.matches_any_pattern?('/root/test12.rb', patterns)).to be false
    end

    it 'does not match dotfiles with * by default' do
      patterns = ['/root/*']
      expect(described_class.matches_any_pattern?('/root/.hidden', patterns)).to be false
    end

    context 'when on case-insensitive filesystems' do
      before do
        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?).and_return(false)
      end

      it 'matches patterns regardless of case in path' do
        patterns = ['/root/lib/*.rb']
        expect(described_class.matches_any_pattern?('/root/LIB/foo.rb', patterns)).to be true
        expect(described_class.matches_any_pattern?('/root/Lib/foo.rb', patterns)).to be true
      end

      it 'matches patterns regardless of case in pattern' do
        patterns = ['/ROOT/LIB/*.RB']
        expect(described_class.matches_any_pattern?('/root/lib/foo.rb', patterns)).to be true
      end

      it 'matches patterns with mixed case in filename' do
        patterns = ['/root/lib/*.rb']
        expect(described_class.matches_any_pattern?('/root/lib/FooBar.rb', patterns)).to be true
        expect(described_class.matches_any_pattern?('/root/lib/FOOBAR.RB', patterns)).to be true
      end

      it 'matches recursive patterns regardless of case' do
        patterns = ['/root/**/*.rb']
        expect(described_class.matches_any_pattern?('/root/LIB/Deeply/NESTED/file.rb',
          patterns)).to be true
      end
    end

    context 'when on case-sensitive filesystems' do
      before do
        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?)
          .and_return(true)
      end

      it 'does not match patterns with different case in path' do
        patterns = ['/root/lib/*.rb']
        expect(described_class.matches_any_pattern?('/root/LIB/foo.rb', patterns)).to be false
        expect(described_class.matches_any_pattern?('/root/Lib/foo.rb', patterns)).to be false
      end

      it 'does not match patterns with different case in pattern' do
        patterns = ['/ROOT/LIB/*.RB']
        expect(described_class.matches_any_pattern?('/root/lib/foo.rb', patterns)).to be false
      end

      it 'matches patterns with exact case match' do
        patterns = ['/root/lib/*.rb']
        expect(described_class.matches_any_pattern?('/root/lib/foo.rb', patterns)).to be true
      end

      it 'does not match simple patterns with different case' do
        patterns = ['/root/LIB/*.rb']
        expect(CovLoupe::PathUtils).to receive(:volume_case_sensitive?)
          .at_least(:once).and_return(true)
        expect(described_class.matches_any_pattern?('/root/lib/file.rb',
          patterns)).to be false
      end
    end

    context 'when volume case-sensitivity detection fails' do
      before do
        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?)
          .and_raise(SystemCallError.new('test error', 1))
      end

      it 'defaults to case-insensitive matching for safety' do
        patterns = ['/root/lib/*.rb']
        expect(described_class.matches_any_pattern?('/root/LIB/foo.rb', patterns)).to be true
      end
    end

    context 'when volume case-sensitivity detection raises IOError' do
      before do
        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?)
          .and_raise(IOError.new('test error'))
      end

      it 'defaults to case-insensitive matching for safety' do
        patterns = ['/root/lib/*.rb']
        expect(described_class.matches_any_pattern?('/root/LIB/foo.rb', patterns)).to be true
      end
    end

    context 'with Windows-style paths' do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with('C:/nonexistent/path/file.rb').and_return(false)
        allow(File).to receive(:directory?).with('C:/nonexistent/path').and_return(false)
        allow(File).to receive(:directory?).with('C:/nonexistent').and_return(false)
        allow(File).to receive(:directory?).with('C:/').and_return(true)

        allow(File).to receive(:dirname).and_call_original
        allow(File).to receive(:dirname).with('C:/nonexistent/path/file.rb').and_return('C:/nonexistent/path')
        allow(File).to receive(:dirname).with('C:/nonexistent/path').and_return('C:/nonexistent')
        allow(File).to receive(:dirname).with('C:/nonexistent').and_return('C:/')
        allow(File).to receive(:dirname).with('C:/').and_return('C:/')

        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?).with('C:/').and_return(false)
      end

      it 'finds root directory on Windows paths without infinite loop' do
        patterns = ['C:/nonexistent/**/*.rb']
        expect(described_class.matches_any_pattern?('C:/nonexistent/path/file.rb', patterns)).to be true
      end
    end
  end

  describe '.filter_by_pattern' do
    let(:items) do
      [
        { 'file' => '/root/lib/foo.rb' },
        { 'file' => '/root/spec/foo_spec.rb' },
        { 'file' => '/root/lib/bar.rb' },
      ]
    end

    it 'returns all items if patterns is nil' do
      expect(described_class.filter_by_pattern(items, nil)).to eq(items)
    end

    it 'returns all items if patterns is empty' do
      expect(described_class.filter_by_pattern(items, [])).to eq(items)
    end

    it 'filters items matching the patterns' do
      patterns = ['/root/lib/*.rb']
      result = described_class.filter_by_pattern(items, patterns)
      expect(result).to contain_exactly(
        { 'file' => '/root/lib/foo.rb' },
        { 'file' => '/root/lib/bar.rb' }
      )
    end

    it 'allows specifying a custom key for file path' do
      custom_items = [
        { 'path' => '/root/lib/foo.rb' },
        { 'path' => '/root/spec/foo_spec.rb' },
      ]
      patterns = ['/root/lib/*.rb']
      result = described_class.filter_by_pattern(custom_items, patterns, key: 'path')
      expect(result).to contain_exactly({ 'path' => '/root/lib/foo.rb' })
    end
  end

  describe 'root-based case-sensitivity detection' do
    it 'probes the volume once for filter_paths regardless of path count' do
      allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?).and_return(true)
      paths = %w[/root/lib/a.rb /root/lib/b.rb /root/spec/c.rb]
      described_class.filter_paths(paths, 'lib/*.rb', root: '/root')
      expect(CovLoupe::PathUtils).to have_received(:volume_case_sensitive?).once
    end

    it 'probes the volume once for filter_by_pattern when root is given' do
      allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?).and_return(true)
      items = [{ 'file' => '/root/lib/a.rb' }, { 'file' => '/root/lib/b.rb' }]
      described_class.filter_by_pattern(items, ['/root/lib/*.rb'], root: '/root')
      expect(CovLoupe::PathUtils).to have_received(:volume_case_sensitive?).once
    end
  end

  describe '.filter_paths' do
    let(:root) { File.expand_path('/project') }
    let(:paths) do
      [
        File.expand_path('/project/lib/foo.rb'),
        File.expand_path('/project/lib/bar.rb'),
        File.expand_path('/project/spec/foo_spec.rb'),
        File.expand_path('/project/spec/bar_spec.rb'),
      ]
    end

    it 'returns all paths when globs is nil' do
      expect(described_class.filter_paths(paths, nil, root: root)).to eq(paths)
    end

    it 'returns all paths when globs is empty array' do
      expect(described_class.filter_paths(paths, [], root: root)).to eq(paths)
    end

    it 'filters paths by a single glob pattern' do
      result = described_class.filter_paths(paths, 'lib/*.rb', root: root)
      expect(result).to contain_exactly(
        File.expand_path('/project/lib/foo.rb'),
        File.expand_path('/project/lib/bar.rb')
      )
    end

    it 'filters paths by multiple glob patterns' do
      result = described_class.filter_paths(paths, ['lib/foo.rb', 'spec/*.rb'], root: root)
      expect(result).to contain_exactly(
        File.expand_path('/project/lib/foo.rb'),
        File.expand_path('/project/spec/foo_spec.rb'),
        File.expand_path('/project/spec/bar_spec.rb')
      )
    end

    it 'handles absolute glob patterns' do
      result = described_class.filter_paths(paths,
        File.expand_path('/project/lib/*.rb'), root: root)
      expect(result).to contain_exactly(
        File.expand_path('/project/lib/foo.rb'),
        File.expand_path('/project/lib/bar.rb')
      )
    end

    it 'supports recursive patterns' do
      nested_paths = [
        File.expand_path('/project/lib/utils/helper.rb'),
        File.expand_path('/project/lib/foo.rb'),
        File.expand_path('/project/spec/foo_spec.rb'),
      ]
      result = described_class.filter_paths(nested_paths, 'lib/**/*.rb', root: root)
      expect(result).to contain_exactly(
        File.expand_path('/project/lib/utils/helper.rb'),
        File.expand_path('/project/lib/foo.rb')
      )
    end

    it 'returns empty array when no paths match' do
      result = described_class.filter_paths(paths, 'src/*.rb', root: root)
      expect(result).to eq([])
    end
  end
end
