# frozen_string_literal: true

require_relative '../errors/errors'

module CovLoupe
  # Parses the CLI's --tracked-globs option value. It lives with the option parsing rather
  # than in GlobUtils, which matches paths against patterns once they are split.
  #
  # @api private
  module GlobListSplitter
    # Splits the CLI's comma-separated --tracked-globs value into individual glob patterns.
    #
    # A plain split(',') is not enough, because commas also appear *inside* glob syntax:
    #
    #   - Brace alternatives: 'app/{models,controllers}/**/*.rb' is ONE pattern meaning
    #     "app/models/**/*.rb or app/controllers/**/*.rb". Braces may nest: '{a,{b,c}}'.
    #   - Character classes: 'x[,;]y' is ONE pattern matching "x,y" or "x;y".
    #
    # So a comma separates patterns only when it is at the top level: outside any {...} and
    # outside a [...]. Every other comma is kept as part of its pattern.
    #
    # For a value containing none of '{', '[' or a backslash, the result is exactly what
    # split(',') gives (minus empty items), so every value that worked before still splits
    # the same way. Only values that used to break apart (commas inside braces or brackets,
    # or after a backslash) now stay together.
    #
    # Backslash escapes follow File.fnmatch, which treats '\x' as a literal 'x' unless
    # FNM_NOESCAPE is set (cov-loupe never sets it). An escaped '{', '[', or ',' therefore
    # does not open a group or split the list. On Windows, though, cov-loupe converts
    # backslashes in patterns to '/' before matching (see fn_normalize_path_separators), so
    # there a backslash is a path separator, not an escape, and is copied like any other
    # character.
    #
    # Braces and brackets are tracked the way Ruby's File.fnmatch reads them:
    #
    #   - Ruby expands braces before it looks at character classes, and its brace matching
    #     ignores '[' and ']'. So every unescaped '{' and '}' counts, even one inside '[...]':
    #     'x[{a],b}c' is the brace group '{a],b}', expanding to 'x[a]c' and 'x[bc'. Its comma
    #     must not split the list.
    #   - A '[' only matters at the top level (brace depth 0), where it protects the commas of
    #     a class such as 'x[,;]y'. Inside braces the whole group is kept together anyway, so
    #     brackets there need no tracking.
    #   - Not followed: a class that opens inside braces and closes after them, as in
    #     '{a[1,2},b]', which Ruby expands to 'a[1,b]' and '2,b]'. The splitter sees the comma
    #     after '}' at the top level and splits there. Patterns like this are too contrived to
    #     be worth expanding braces for.
    #
    # Empty items ('a,,b', a trailing comma, or an empty value) are dropped. (The Array type
    # previously used for this option returned nil for them instead.)
    #
    # @param value [String] the raw --tracked-globs argument, e.g. 'lib/**/*.rb,app/{a,b}/*.rb'
    # @return [Array<String>] the individual patterns, in order
    # @raise [UsageError] if a '{', or a '[' outside braces, is never closed. CRuby's
    #   File.fnmatch matches nothing for such a pattern, so it would silently select no files.
    #   JRuby reads an unmatched '{' as a literal character instead; it is rejected there too,
    #   so a value means the same on every engine. The message says how to match the bracket
    #   literally: '[[]' for '[', and '\{' for '{' except on Windows, where a backslash is a
    #   path separator.
    module_function def split(value)
      backslashes_are_escapes = !CovLoupe.windows?
      patterns = []
      current = +'' # the pattern being built; unfrozen, since characters are appended
      brace_depth = 0 # how many '{' are open; a comma splits only at depth 0
      in_class = false # inside a top-level '[...]' character class
      escaped = false # the previous character was an escaping backslash

      value.each_char do |char|
        if escaped
          # The character after a backslash is literal: it never opens or closes a group or
          # splits the list. Both the backslash and the character stay in the pattern, so
          # File.fnmatch still sees the escape.
          escaped = false
        elsif char == '\\' && backslashes_are_escapes
          escaped = true
        elsif char == '{'
          # Checked before the class state: Ruby treats a '{' as brace syntax even inside '[...]'.
          brace_depth += 1
        elsif char == '}'
          # A '}' with no open '{' is a literal character, so the depth never goes negative.
          brace_depth -= 1 if brace_depth.positive?
        elsif in_class
          # Inside '[...]', apart from braces, only ']' matters: it ends the class. A comma here
          # is a class member, not a separator. Ruby also ends a class at a ']' right after the
          # '[', so '[]' is an empty class that matches nothing. It is accepted, as in 6.x:
          # it is closed, so it cannot swallow the commas after it.
          in_class = false if char == ']'
        elsif char == '[' && brace_depth.zero?
          in_class = true
        elsif char == ',' && brace_depth.zero?
          # A top-level comma ends the current pattern. The comma itself is not part of
          # either pattern, so skip appending it.
          patterns << current
          current = +''
          next
        end

        current << char
      end

      # An unclosed '{' or '[' would otherwise swallow the rest of the value, including any
      # commas meant to separate patterns, into one pattern that CRuby's File.fnmatch matches
      # nothing with (see @raise above for JRuby). Fail loudly instead of silently selecting no
      # files. value.inspect keeps the message on one line even if the value has a newline.
      if brace_depth.positive? || in_class
        bracket = brace_depth.positive? ? '{' : '['
        # Say how to match the bracket literally, where that can be written. '[[]' (a class
        # holding only '[') works everywhere. '\{' works only where a backslash escapes; '[{]'
        # would not help, since braces count even inside a class. So on Windows the brace
        # message has no hint. A shell, and Shellwords for COV_LOUPE_OPTS, removes an unquoted
        # backslash, so the '\{' hint says to quote it.
        hint =
          if bracket == '['
            ". To match a literal '[', write '[[]'"
          elsif backslashes_are_escapes
            ". To match a literal '{', write '\\{', quoted so the shell keeps the backslash"
          else
            ''
          end
        raise UsageError, "Unclosed '#{bracket}' in --tracked-globs value: #{value.inspect}#{hint}"
      end

      patterns << current
      patterns.reject(&:empty?)
    end
  end
end
