# frozen_string_literal: true

# This file exists in the project but is never loaded by tests,
# so it won't appear in coverage data. Used to test detecting files that are not in coverage data.
class UncoveredFile
  def self.hello
    puts 'Hello from an uncovered file'
  end
end
