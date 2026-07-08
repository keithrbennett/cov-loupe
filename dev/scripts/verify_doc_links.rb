#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'find'
require 'net/http'
require 'optparse'
require 'pathname'
require 'uri'

class DocLinkVerifier
  EXCLUDED_PATH_PARTS = %w[
    .bundle
    .docs-venv
    .git
    .venv
    coverage
    node_modules
    site
    tmp
    vendor
  ].freeze

  LOCAL_SCHEMES = [nil, ''].freeze
  SKIPPED_SCHEMES = %w[mailto tel javascript].freeze

  DEFAULT_OPTIONS = {
    all_markdown:   false,
    check_external: false,
    raw:            true,
    root:           Pathname.new(Dir.pwd).expand_path,
    server:         true,
    server_url:     'http://127.0.0.1:8000/',
    timeout:        8,
  }.freeze

  Link = Struct.new(:source, :line, :target, :kind, keyword_init: true)

  def initialize(options)
    @options = options
    @root = options.fetch(:root)
    @errors = []
    @warnings = []
  end

  def call
    verify_raw_markdown if @options.fetch(:raw)
    verify_server if @options.fetch(:server)

    print_results
    @errors.empty?
  end

  attr_reader :root

  private def verify_raw_markdown
    markdown_files.each do |file|
      links_from_markdown(file).each do |link|
        verify_raw_link(link)
      end
    end
  end

  private def verify_server
    base_uri = URI(@options.fetch(:server_url))
    response = http_get(base_uri)

    unless response_success?(response)
      add_error('doc server', 0, base_uri.to_s, "server returned #{response.code}")
      return
    end

    crawled = {}
    queued = [normalize_server_uri(base_uri)]
    visited_assets = {}

    until queued.empty?
      page_uri = queued.shift
      next if crawled.key?(page_uri.to_s)

      crawled[page_uri.to_s] = true
      response = http_get(page_uri)

      unless response_success?(response)
        add_error(page_uri.to_s, 0, page_uri.to_s, "server returned #{response.code}")
        next
      end

      body = response.body
      page_ids = html_ids(body)

      links_from_html(page_uri, body).each do |link|
        target_uri = absolute_uri(page_uri, link.target)
        next unless target_uri

        if skipped_scheme?(target_uri.scheme)
          next
        elsif external_uri?(base_uri, target_uri)
          verify_external_link(link, target_uri)
        elsif page_link?(target_uri)
          queued << normalize_server_uri(target_uri)
          verify_server_page_link(link, target_uri, page_ids, page_uri)
        else
          verify_server_asset_link(link, target_uri, visited_assets)
        end
      end
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    add_error('doc server', 0, base_uri.to_s, "#{e.class}: #{e.message}")
  end

  private def markdown_files
    tracked = tracked_markdown_files
    return tracked unless tracked.empty?

    filesystem_markdown_files
  end

  private def tracked_markdown_files
    paths = IO.popen(['git', '-C', root.to_s, 'ls-files', '*.md'], &:read).lines.map(&:chomp)
    paths
      .select { |path| @options.fetch(:all_markdown) || doc_markdown_path?(path) }
      .map { |path| root.join(path) }
      .select(&:file?)
      .sort
  rescue Errno::ENOENT
    []
  end

  private def filesystem_markdown_files
    files = []

    Find.find(root.to_s) do |path|
      relative = Pathname.new(path).relative_path_from(root).to_s

      if File.directory?(path)
        Find.prune if excluded_path?(relative)
        next
      end

      files << Pathname.new(path) if path.end_with?('.md')
    end

    files.select do |path|
      @options.fetch(:all_markdown) || doc_markdown_path?(path.relative_path_from(root).to_s)
    end.sort
  end

  private def doc_markdown_path?(path)
    path.start_with?('docs/') || !path.include?('/')
  end

  private def excluded_path?(relative)
    parts = relative.split(File::SEPARATOR)
    parts.intersect?(EXCLUDED_PATH_PARTS)
  end

  private def links_from_markdown(file)
    text = file.read
    links = []
    in_fence = false

    text.each_line.with_index(1) do |line, line_number|
      if fenced_code_boundary?(line)
        in_fence = !in_fence
        next
      end

      next if in_fence

      line.scan(/!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) do |match|
        links << Link.new(source: file, line: line_number, target: match.first, kind: :markdown)
      end

      line.scan(/<(a|img)\b[^>]*(?:href|src)=["']([^"']+)["'][^>]*>/i) do |match|
        links << Link.new(source: file, line: line_number, target: match.last, kind: :html)
      end
    end

    links
  end

  private def fenced_code_boundary?(line)
    line.match?(/^\s*(```|~~~)/)
  end

  private def verify_raw_link(link)
    uri = parse_uri(link.target)
    return unless uri
    return if skipped_scheme?(uri.scheme)

    if LOCAL_SCHEMES.include?(uri.scheme)
      verify_raw_local_link(link, uri)
    else
      verify_external_link(link, uri)
    end
  end

  private def verify_raw_local_link(link, uri)
    path_part = uri.path.to_s
    fragment = uri.fragment

    target_path = if path_part.empty?
      Pathname.new(link.source)
    elsif path_part.start_with?('/')
      root.join(path_part.delete_prefix('/'))
    else
      Pathname.new(link.source).dirname.join(percent_decode(path_part))
    end

    target_path = target_path.cleanpath

    unless target_path.exist?
      add_error(link.source, link.line, link.target, "missing file #{target_path.relative_path_from(root)}")
      return
    end

    return unless fragment && markdown_file?(target_path)

    anchors = markdown_anchors(target_path)
    return if anchors.include?(fragment)

    add_error(link.source, link.line, link.target,
      "missing anchor ##{fragment} in #{target_path.relative_path_from(root)}")
  end

  private def markdown_file?(path)
    path.extname.downcase == '.md'
  end

  private def markdown_anchors(file)
    anchors = []

    file.each_line do |line|
      if (heading = line.match(/^\s{0,3}\#{1,6}\s+(.+?)\s*\#*\s*$/))
        text = heading[1].gsub(/\{#([^}]+)\}\s*$/, '')
        anchors.push(github_anchor(text), mkdocs_anchor(text))
      end

      line.scan(/\{#([^}]+)\}/) { |match| anchors << match.first }
      line.scan(/<[^>]+\sid=["']([^"']+)["'][^>]*>/i) { |match| anchors << match.first }
    end

    anchors.uniq
  end

  private def github_anchor(text)
    text
      .downcase
      .gsub(/<[^>]+>/, '')
      .gsub(/`([^`]+)`/, '\1')
      .gsub(/[^\p{Alnum}\s-]/, '')
      .strip
      .gsub(/\s+/, '-')
  end

  private def mkdocs_anchor(text)
    text
      .downcase
      .gsub(/<[^>]+>/, '')
      .gsub(/`([^`]+)`/, '\1')
      .gsub(/[^\p{Alnum}\s_-]/, '')
      .strip
      .gsub(/\s+/, '-')
  end

  private def links_from_html(source_uri, html)
    links = []

    html.scan(/<(a|link|script|img)\b[^>]*(?:href|src)=["']([^"']+)["'][^>]*>/i) do |match|
      links << Link.new(source: source_uri, line: 0, target: CGI.unescapeHTML(match.last), kind: :html)
    end

    links
  end

  private def verify_server_page_link(link, target_uri, current_page_ids, page_uri)
    target_without_fragment = normalize_server_uri(target_uri)

    if target_without_fragment == normalize_server_uri(page_uri)
      verify_server_fragment(link, target_uri.fragment, current_page_ids)
      return
    end

    response = http_get(target_without_fragment)

    unless response_success?(response)
      add_error(link.source, link.line, link.target, "server returned #{response.code}")
      return
    end

    verify_server_fragment(link, target_uri.fragment, html_ids(response.body))
  end

  private def verify_server_fragment(link, fragment, ids)
    return if fragment.nil? || fragment.empty? || ids.include?(fragment)

    add_error(link.source, link.line, link.target, "missing server anchor ##{fragment}")
  end

  private def verify_server_asset_link(link, target_uri, visited_assets)
    normalized = normalize_server_uri(target_uri)
    return if visited_assets.key?(normalized.to_s)

    visited_assets[normalized.to_s] = true
    response = http_head_or_get(normalized)
    return if response_success?(response)

    add_error(link.source, link.line, link.target, "server returned #{response.code}")
  end

  private def verify_external_link(link, uri)
    return unless @options.fetch(:check_external)

    response = http_head_or_get(uri)
    return if response_success?(response)

    add_error(link.source, link.line, link.target, "external link returned #{response.code}")
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error => e
    add_error(link.source, link.line, link.target, "#{e.class}: #{e.message}")
  end

  private def html_ids(html)
    ids = []
    html.scan(/\sid=["']([^"']+)["']/i) { |match| ids << CGI.unescapeHTML(match.first) }
    ids.uniq
  end

  private def page_link?(uri)
    path = uri.path.to_s
    File.extname(path).empty? || path.end_with?('.html')
  end

  private def external_uri?(base_uri, uri)
    uri.host != base_uri.host || uri.port != base_uri.port || uri.scheme != base_uri.scheme
  end

  private def normalize_server_uri(uri)
    normalized = uri.dup
    normalized.fragment = nil
    normalized.query = nil
    normalized.path = '/' if normalized.path.nil? || normalized.path.empty?
    normalized
  end

  private def absolute_uri(base_uri, target)
    base_uri + target
  rescue URI::InvalidURIError
    add_error(base_uri.to_s, 0, target, 'invalid URI')
    nil
  end

  private def parse_uri(target)
    URI(target)
  rescue URI::InvalidURIError => e
    add_error('raw markdown', 0, target, "invalid URI: #{e.message}")
    nil
  end

  private def skipped_scheme?(scheme)
    SKIPPED_SCHEMES.include?(scheme.to_s.downcase)
  end

  private def response_success?(response)
    response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
  end

  private def http_head_or_get(uri)
    response = http_request(uri, Net::HTTP::Head)
    return response unless response.is_a?(Net::HTTPMethodNotAllowed)

    http_get(uri)
  end

  private def http_get(uri)
    http_request(uri, Net::HTTP::Get)
  end

  private def http_request(uri, request_class)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @options.fetch(:timeout)
    http.read_timeout = @options.fetch(:timeout)
    http.use_ssl = uri.scheme == 'https'

    request = request_class.new(uri)
    request['User-Agent'] = 'cov-loupe-doc-link-verifier'
    http.request(request)
  end

  private def percent_decode(text)
    CGI.unescape(text)
  end

  private def add_error(source, line, target, message)
    @errors << format_finding(source, line, target, message)
  end

  private def format_finding(source, line, target, message)
    location = if source.is_a?(Pathname)
      source.relative_path_from(root).to_s
    else
      source.to_s
    end
    location += ":#{line}" if line.positive?

    "#{location}: #{target} - #{message}"
  end

  private def print_results
    puts "Checked raw markdown links: #{@options.fetch(:raw) ? 'yes' : 'no'}"
    puts "Checked doc server links: #{@options.fetch(:server) ? @options.fetch(:server_url) : 'no'}"
    puts "Checked external links: #{@options.fetch(:check_external) ? 'yes' : 'no'}"

    unless @warnings.empty?
      puts "\nWarnings:"
      @warnings.each { |warning| puts "  - #{warning}" }
    end

    if @errors.empty?
      puts "\nAll checked doc links are valid."
    else
      warn "\nBroken doc links:"
      @errors.each { |error| warn "  - #{error}" }
    end
  end
end

options = DocLinkVerifier::DEFAULT_OPTIONS.dup

OptionParser.new do |parser|
  parser.banner = 'Usage: ruby dev/scripts/verify_doc_links.rb [options]'

  parser.on('--root PATH', 'Repository root to scan') do |path|
    options[:root] = Pathname.new(path).expand_path
  end

  parser.on('--server-url URL', 'Running MkDocs server URL') do |url|
    options[:server_url] = url
  end

  parser.on('--[no-]raw', 'Enable or disable raw markdown link checks') do |raw|
    options[:raw] = raw
  end

  parser.on('--[no-]server', 'Enable or disable running doc server checks') do |server|
    options[:server] = server
  end

  parser.on('--all-markdown', 'Scan every tracked Markdown file, not just docs and top-level Markdown') do
    options[:all_markdown] = true
  end

  parser.on('--check-external', 'Check HTTP(S) links outside this repository/server') do
    options[:check_external] = true
  end

  parser.on('--timeout SECONDS', Integer, 'HTTP timeout per request') do |seconds|
    options[:timeout] = seconds
  end
end.parse!

exit(DocLinkVerifier.new(options).call ? 0 : 1)
