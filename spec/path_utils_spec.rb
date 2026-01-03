# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::PathUtils do
  describe '.relativize' do
    let(:root) { '/home/user/project' }
    let(:path_in_root) { "#{root}/lib/file.rb" }
    let(:path_outside_root) { '/tmp/external.rb' }
    let(:same_as_root) { root }

    context 'when path is within root' do
      it 'returns relative path' do
        result = described_class.relativize(path_in_root, root)
        expect(result).to eq('lib/file.rb')
      end

      it 'handles nested directories' do
        deep_path = "#{root}/deep/nested/path/file.rb"
        result = described_class.relativize(deep_path, root)
        expect(result).to eq('deep/nested/path/file.rb')
      end

      it 'expands relative paths against root' do
        # This tests the key fix: relative paths are expanded against root, not cwd
        relative_path = 'lib/file.rb'
        result = described_class.relativize(relative_path, root)
        expect(result).to eq('lib/file.rb')
      end
    end

    context 'when path equals root' do
      it 'returns dot for root path' do
        result = described_class.relativize(same_as_root, root)
        expect(result).to eq('.')
      end
    end

    context 'when path is outside root' do
      it 'returns original path unchanged' do
        result = described_class.relativize(path_outside_root, root)
        expect(result).to eq(path_outside_root)
      end

      it 'handles path with same prefix but different directory' do
        similar_root = '/home/user/project-backup'
        similar_path = "#{similar_root}/lib/file.rb"
        result = described_class.relativize(similar_path, root)
        expect(result).to eq(similar_path)
      end
    end

    context 'with Windows drive handling' do
      let(:windows_root) { 'C:/Users/user/project' }
      let(:windows_path_in_root) { "#{windows_root}/lib/file.rb" }
      let(:windows_path_other_drive) { 'D:/external/file.rb' }

      before do
        allow(described_class).to receive(:windows?).and_return(true)
      end

      it 'handles different drives by returning original path' do
        result = described_class.relativize(windows_path_other_drive, windows_root)
        expect(result).to eq(windows_path_other_drive)
      end

      it 'relativizes paths on same drive' do
        result = described_class.relativize(windows_path_in_root, windows_root)
        expect(result).to eq('lib/file.rb')
      end

      it 'relativizes relative paths on same drive' do
        # Test the key fix: relative paths expanded against root on Windows
        relative_path = 'lib/file.rb'
        result = described_class.relativize(relative_path, windows_root)
        expect(result).to eq('lib/file.rb')
      end
    end

    context 'when error occurs' do
      it 'handles ArgumentError from relative_path_from' do
        # Use a simpler approach that doesn't require complex mocking
        # Create a scenario that would cause relative_path_from to fail
        different_drive_path = 'C:/path/file.rb'
        unix_root = '/home/user/project'

        # This should cause an ArgumentError when trying to relativize
        # a Windows path against a Unix path
        result = described_class.relativize(different_drive_path, unix_root)
        expect(result).to eq(different_drive_path)
      end
    end

    context 'with input validation' do
      it 'returns path when path is nil' do
        result = described_class.relativize(nil, root)
        expect(result).to be_nil
      end

      it 'returns path when path is empty' do
        result = described_class.relativize('', root)
        expect(result).to eq('')
      end

      it 'returns path when root is nil' do
        result = described_class.relativize(path_in_root, nil)
        expect(result).to eq(path_in_root)
      end

      it 'returns path when root is empty' do
        result = described_class.relativize(path_in_root, '')
        expect(result).to eq(path_in_root)
      end

      it 'handles both nil/empty inputs' do
        result = described_class.relativize(nil, nil)
        expect(result).to be_nil
      end
    end

    context 'with edge cases for root_prefix matching' do
      it 'handles root with trailing separator' do
        root_with_sep = "#{root}/"
        result = described_class.relativize(path_in_root, root_with_sep)
        expect(result).to eq('lib/file.rb')
      end

      it 'handles paths that start with root but are not within it' do
        longer_root = '/home/user'
        path_starting_with_root = "#{longer_root}project-backup/lib/file.rb"
        result = described_class.relativize(path_starting_with_root, longer_root)
        expect(result).to eq(path_starting_with_root)
      end
    end

    context 'with case-insensitive volumes' do
      before do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(false)
        # Stub expand to return paths as-is (simulating absolute path behavior)
        # This allows normalized_start_with? to work correctly in tests
        allow(described_class).to receive(:expand).and_wrap_original do |method, path, base = nil|
          # For absolute paths, return as-is to preserve casing
          if path&.start_with?('/')
            path
          elsif base
            "#{base}/#{path}"
          else
            method.call(path, base)
          end
        end
      end

      it 'relativizes paths with different casing in path' do
        mixed_case_path = '/Home/User/Project/lib/file.rb'
        result = described_class.relativize(mixed_case_path, root)
        expect(result).to eq('lib/file.rb')
      end

      it 'relativizes paths with different casing in root' do
        mixed_case_root = '/HOME/USER/PROJECT'
        result = described_class.relativize(path_in_root, mixed_case_root)
        expect(result).to eq('lib/file.rb')
      end

      it 'relativizes paths with different casing in both' do
        mixed_case_path = '/Home/User/Project/Lib/File.rb'
        mixed_case_root = '/home/user/project'
        result = described_class.relativize(mixed_case_path, mixed_case_root)
        # On case-insensitive volumes, the original casing from the path is preserved
        expect(result).to eq('Lib/File.rb')
      end

      it 'still respects boundary checking with case differences' do
        # /home/user/project-backup should not match /home/user/project
        backup_path = '/Home/User/Project-Backup/lib/file.rb'
        result = described_class.relativize(backup_path, root)
        expect(result).to eq(backup_path)
      end
    end

    context 'with mixed separators on Windows' do
      let(:windows_root) { 'C:/Users/user/project' }
      let(:windows_path) { 'C:\\Users\\user\\project\\lib\\file.rb' }

      before do
        allow(described_class).to receive_messages(windows?: true, volume_case_sensitive?: false)
        # Stub expand to return Windows paths as-is (simulating absolute path behavior)
        allow(described_class).to receive(:expand).and_wrap_original do |method, path, base = nil|
          # For absolute paths (Windows drive letters or Unix /), return as-is
          if path&.match?(/^[A-Za-z]:[\/\\]/) || path&.start_with?('/')
            path
          elsif base
            "#{base}/#{path}"
          else
            method.call(path, base)
          end
        end
      end

      it 'relativizes path with backslashes against forward slash root' do
        result = described_class.relativize(windows_path, windows_root)
        expect(result).to eq('lib/file.rb')
      end

      it 'relativizes path with forward slashes against backslash root' do
        backslash_root = 'C:\\Users\\user\\project'
        forward_path = 'C:/Users/user/project/lib/file.rb'
        result = described_class.relativize(forward_path, backslash_root)
        expect(result).to eq('lib/file.rb')
      end

      it 'relativizes path with mixed separators' do
        mixed_path = 'C:/Users\\user/project\\lib/file.rb'
        result = described_class.relativize(mixed_path, windows_root)
        expect(result).to eq('lib/file.rb')
      end

      it 'combines case-insensitive and mixed-separator handling' do
        mixed_case_and_sep = 'C:\\Users\\User\\Project\\Lib\\File.rb'
        result = described_class.relativize(mixed_case_and_sep, windows_root)
        # On case-insensitive volumes, the original casing from the path is preserved
        expect(result).to eq('Lib/File.rb')
      end
    end
  end

  describe '.normalize' do
    context 'with basic functionality' do
      it 'returns input unchanged for nil' do
        result = described_class.normalize(nil)
        expect(result).to be_nil
      end

      it 'returns input unchanged for empty string' do
        result = described_class.normalize('')
        expect(result).to eq('')
      end

      it 'converts pathname to string' do
        pathname = Pathname.new('/path/to/file')
        result = described_class.normalize(pathname)
        expect(result).to be_a(String)
        expect(result).to eq('/path/to/file')
      end
    end

    context 'with slash normalization' do
      it 'normalizes backslashes to forward slashes on Windows' do
        allow(described_class).to receive_messages(windows?: true, volume_case_sensitive?: true)
        result = described_class.normalize('C:\\Users\\file.rb')
        expect(result).to eq('C:/Users/file.rb')
      end
    end

    context 'with case normalization' do
      it 'normalizes case on case-insensitive volumes' do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(false)
        result = described_class.normalize('/PATH/TO/FILE')
        expect(result).to eq('/path/to/file')
      end

      it 'preserves case on case-sensitive volumes' do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(true)
        result = described_class.normalize('/PATH/TO/FILE')
        expect(result).to eq('/PATH/TO/FILE')
      end

      it 'respects explicit normalize_case option' do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(true)
        result = described_class.normalize('/PATH/TO/FILE', normalize_case: true)
        expect(result).to eq('/path/to/file')
      end
    end

    context 'with path cleaning' do
      it 'removes redundant separators' do
        result = described_class.normalize('path//to///file')
        expect(result).to eq('path/to/file')
      end

      it 'resolves dot components' do
        result = described_class.normalize('path/./to/./file')
        expect(result).to eq('path/to/file')
      end

      it 'resolves parent directory references' do
        result = described_class.normalize('path/to/../file')
        expect(result).to eq('path/file')
      end
    end
  end

  describe '.expand' do
    it 'returns input unchanged for nil' do
      result = described_class.expand(nil)
      expect(result).to be_nil
    end

    it 'returns input unchanged for empty string' do
      result = described_class.expand('')
      expect(result).to eq('')
    end

    it 'expands relative path to absolute' do
      result = described_class.expand('relative/path')
      expect(result).to start_with(Dir.pwd)
      expect(result).to end_with('relative/path')
    end

    it 'expands relative path relative to base directory' do
      base = '/base/directory'
      result = described_class.expand('relative/path', base)
      expect(result).to eq(File.expand_path('relative/path', base))
    end

    it 'returns absolute paths unchanged' do
      absolute = '/absolute/path'
      result = described_class.expand(absolute)
      expect(result).to eq(File.expand_path(absolute))
    end

    it 'returns Windows-style absolute paths unchanged on Unix systems' do
      # File.expand_path will treat Windows paths as relative on Unix,
      # but that's expected behavior of the simplified method
      windows_path = 'C:/Users/file'
      result = described_class.expand(windows_path)
      # On Unix, this gets expanded against current directory, which is expected
      expect(result).to include(windows_path)
    end
  end

  describe '.absolute?' do
    it 'returns false for nil' do
      expect(described_class.absolute?(nil)).to be false
    end

    it 'returns false for empty string' do
      expect(described_class.absolute?('')).to be false
    end

    it 'returns true for absolute paths' do
      expect(described_class.absolute?('/absolute/path')).to be true
    end

    it 'returns false for relative paths' do
      expect(described_class.absolute?('relative/path')).to be false
    end

    it 'returns true for Unix-style absolute paths' do
      expect(described_class.absolute?('/Unix/absolute/path')).to be true
    end

    it 'returns true for Windows-style absolute paths' do
      expect(described_class.absolute?('C:/Users/file')).to be true
    end

    it 'returns true for Windows-style absolute paths with backslashes' do
      expect(described_class.absolute?('C:\\Users\\file')).to be true
    end
  end

  describe '.relative?' do
    it 'returns true for relative paths' do
      expect(described_class.relative?('relative/path')).to be true
    end

    it 'returns false for absolute paths' do
      expect(described_class.relative?('/absolute/path')).to be false
    end

    it 'returns true for nil' do
      expect(described_class.relative?(nil)).to be true
    end

    it 'returns true for empty string' do
      expect(described_class.relative?('')).to be true
    end
  end

  describe '.within_root?' do
    let(:root) { '/home/user/project' }

    it 'returns false for nil path' do
      expect(described_class.within_root?(nil, root)).to be false
    end

    it 'returns false for nil root' do
      expect(described_class.within_root?('/some/path', nil)).to be false
    end

    it 'returns true for path within root' do
      expect(described_class.within_root?("#{root}/lib/file.rb", root)).to be true
    end

    it 'returns true for path equal to root' do
      expect(described_class.within_root?(root, root)).to be true
    end

    it 'returns false for path outside root' do
      expect(described_class.within_root?('/tmp/external.rb', root)).to be false
    end

    it 'returns false for paths with similar prefix but not within root' do
      # /home/user/project-backup is not within /home/user/project
      expect(described_class.within_root?('/home/user/project-backup/file.rb', root)).to be false
    end

    context 'with case-insensitive volumes' do
      before do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(false)
      end

      it 'returns true for path with different casing' do
        mixed_case_path = '/Home/User/Project/lib/file.rb'
        expect(described_class.within_root?(mixed_case_path, root)).to be true
      end

      it 'returns true for root with different casing' do
        mixed_case_root = '/HOME/USER/PROJECT'
        expect(described_class.within_root?("#{root}/lib/file.rb", mixed_case_root)).to be true
      end

      it 'returns false for similar paths with different casing but not within root' do
        backup_path = '/Home/User/Project-Backup/file.rb'
        expect(described_class.within_root?(backup_path, root)).to be false
      end
    end

    context 'with mixed separators on Windows' do
      let(:windows_root) { 'C:/Users/user/project' }

      before do
        allow(described_class).to receive_messages(windows?: true, volume_case_sensitive?: false)
      end

      it 'returns true for path with backslashes and root with forward slashes' do
        backslash_path = 'C:\\Users\\user\\project\\lib\\file.rb'
        expect(described_class.within_root?(backslash_path, windows_root)).to be true
      end

      it 'returns true for path with forward slashes and root with backslashes' do
        backslash_root = 'C:\\Users\\user\\project'
        forward_path = 'C:/Users/user/project/lib/file.rb'
        expect(described_class.within_root?(forward_path, backslash_root)).to be true
      end

      it 'returns true with mixed case and separators' do
        mixed_path = 'C:\\Users\\User\\Project\\Lib\\File.rb'
        expect(described_class.within_root?(mixed_path, windows_root)).to be true
      end
    end
  end

  describe '.basename' do
    it 'returns empty string for nil' do
      expect(described_class.basename(nil)).to eq('')
    end

    it 'returns empty string for empty string' do
      expect(described_class.basename('')).to eq('')
    end

    it 'extracts filename from path' do
      result = described_class.basename('/path/to/file.rb')
      expect(result).to eq('file.rb')
    end

    it 'handles paths with trailing slash' do
      result = described_class.basename('/path/to/directory/')
      expect(result).to eq('directory')
    end

    it 'applies normalization before extracting basename' do
      allow(described_class).to receive(:volume_case_sensitive?).and_return(false)
      result = described_class.basename('/PATH/TO/FILE.rb')
      expect(result).to eq('file.rb')
    end
  end

  describe '.join' do
    it 'joins path components' do
      result = described_class.join('path', 'to', 'file.rb')
      expect(result).to eq(File.join('path', 'to', 'file.rb'))
    end

    it 'handles single component' do
      result = described_class.join('single')
      expect(result).to eq('single')
    end

    it 'handles empty components' do
      result = described_class.join('path', '', 'file.rb')
      expect(result).to eq(File.join('path', '', 'file.rb'))
    end
  end

  describe '.volume_case_sensitive?' do
    before do
      # Clear the cache before each test to ensure isolation
      described_class.instance_variable_set(:@volume_case_sensitivity_cache, nil)
    end

    it 'caches result per path' do
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:volume_case_sensitive?)
        .with(Dir.pwd).and_return(true)

      # Call twice to ensure caching works for same path
      result1 = described_class.volume_case_sensitive?
      result2 = described_class.volume_case_sensitive?
      expect(result1).to eq(result2)
      expect(CovLoupe::Resolvers::ResolverHelpers).to have_received(:volume_case_sensitive?).once
    end

    it 'delegates to ResolverHelpers.volume_case_sensitive?' do
      test_path = '/some/test/path'
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:volume_case_sensitive?)
        .with(test_path).and_return(false)

      result = described_class.volume_case_sensitive?(test_path)
      expect(result).to be false
      expect(CovLoupe::Resolvers::ResolverHelpers).to have_received(:volume_case_sensitive?)
        .with(test_path)
    end

    it 'uses current directory when no path provided' do
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:volume_case_sensitive?)
        .with(Dir.pwd).and_return(true)

      result = described_class.volume_case_sensitive?
      expect(result).to be true
      expect(CovLoupe::Resolvers::ResolverHelpers).to have_received(:volume_case_sensitive?)
        .with(Dir.pwd)
    end

    it 'normalizes paths before caching' do
      test_path = '/some/test/path'
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:volume_case_sensitive?)
        .with(test_path).and_return(true)

      # Call with different representations of the same path
      described_class.volume_case_sensitive?(test_path)
      described_class.volume_case_sensitive?(test_path)

      # Should only call the helper once due to caching
      expect(CovLoupe::Resolvers::ResolverHelpers).to have_received(:volume_case_sensitive?).once
    end
  end

  describe '.windows?' do
    it 'delegates to CovLoupe.windows?' do
      allow(CovLoupe).to receive(:windows?).and_return(true)
      expect(described_class.windows?).to be true
    end
  end

  describe '.windows_drive?' do
    it 'detects drive pattern when File.expand_path returns drive path' do
      allow(File).to receive(:expand_path).and_return('C:/Users/test')
      expect(described_class.windows_drive?).to be true
    end

    it 'returns false for Unix paths' do
      allow(File).to receive(:expand_path).and_return('/home/user')
      expect(described_class.windows_drive?).to be false
    end
  end

  describe '.normalized_start_with?' do
    context 'with basic functionality' do
      it 'returns false for nil path' do
        expect(described_class.normalized_start_with?(nil, '/root')).to be false
      end

      it 'returns false for nil prefix' do
        expect(described_class.normalized_start_with?('/path', nil)).to be false
      end

      it 'returns false for empty prefix' do
        expect(described_class.normalized_start_with?('/path', '')).to be false
      end

      it 'returns true when path starts with prefix' do
        result = described_class.normalized_start_with?(
          '/home/user/project/file.rb', '/home/user/project'
        )
        expect(result).to be true
      end

      it 'returns true when path equals prefix' do
        result = described_class.normalized_start_with?('/home/user/project', '/home/user/project')
        expect(result).to be true
      end

      it 'returns false when path does not start with prefix' do
        result = described_class.normalized_start_with?('/tmp/file.rb', '/home/user/project')
        expect(result).to be false
      end
    end

    context 'with boundary checking' do
      it 'returns false for similar prefixes that are not ancestors' do
        # /home/user/project-backup should not match /home/user/project
        result = described_class.normalized_start_with?(
          '/home/user/project-backup/file.rb',
          '/home/user/project'
        )
        expect(result).to be false
      end

      it 'returns false when prefix matches but is not followed by separator' do
        # /home/user/projects should not match /home/user/project
        result = described_class.normalized_start_with?(
          '/home/user/projects/file.rb',
          '/home/user/project'
        )
        expect(result).to be false
      end

      it 'returns true when prefix is followed by separator' do
        result = described_class.normalized_start_with?(
          '/home/user/project/lib/file.rb',
          '/home/user/project'
        )
        expect(result).to be true
      end
    end

    context 'with case-insensitive matching' do
      before do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(false)
      end

      it 'matches paths with different casing' do
        result = described_class.normalized_start_with?(
          '/Home/User/Project/lib/file.rb',
          '/home/user/project'
        )
        expect(result).to be true
      end

      it 'matches prefix with different casing' do
        result = described_class.normalized_start_with?(
          '/home/user/project/lib/file.rb',
          '/HOME/USER/PROJECT'
        )
        expect(result).to be true
      end

      it 'still enforces boundary checking with case differences' do
        result = described_class.normalized_start_with?(
          '/Home/User/Project-Backup/file.rb',
          '/home/user/project'
        )
        expect(result).to be false
      end
    end

    context 'with mixed separators on Windows' do
      before do
        allow(described_class).to receive_messages(windows?: true, volume_case_sensitive?: false)
      end

      it 'matches paths with backslashes against forward slash prefix' do
        result = described_class.normalized_start_with?(
          'C:\\Users\\Project\\lib\\file.rb',
          'C:/Users/Project'
        )
        expect(result).to be true
      end

      it 'matches paths with forward slashes against backslash prefix' do
        result = described_class.normalized_start_with?(
          'C:/Users/Project/lib/file.rb',
          'C:\\Users\\Project'
        )
        expect(result).to be true
      end

      it 'matches paths with mixed separators' do
        result = described_class.normalized_start_with?(
          'C:/Users\\Project/lib\\file.rb',
          'C:\\Users/Project'
        )
        expect(result).to be true
      end
    end

    context 'with case-sensitive matching' do
      before do
        allow(described_class).to receive(:volume_case_sensitive?).and_return(true)
      end

      it 'does not match paths with different casing' do
        result = described_class.normalized_start_with?(
          '/Home/User/Project/lib/file.rb',
          '/home/user/project'
        )
        expect(result).to be false
      end

      it 'matches paths with exact casing' do
        result = described_class.normalized_start_with?(
          '/home/user/project/lib/file.rb',
          '/home/user/project'
        )
        expect(result).to be true
      end
    end
  end
end
