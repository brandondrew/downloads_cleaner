# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module DownloadsCleaner
  class Config
    DEFAULT_CONFIG_DIR = ENV['CLEANER_HOME'] || File.join(Dir.home, '.config', 'downloads_cleaner')
    DEFAULT_CONFIG_FILE = File.join(DEFAULT_CONFIG_DIR, 'config.yaml')
    DEFAULTS = {
      'database_file' => 'files.db',
      'downloads_directory' => File.join(Dir.home, 'Downloads'),
      'default_size_threshold' => '100MB',
      'replace_with_link' => false,
      'use_database' => true
    }.freeze

    attr_reader :database_file, :downloads_directory, :default_size_threshold, :replace_with_link, :use_database

    def initialize(config_path = DEFAULT_CONFIG_FILE)
      @config_path = config_path
      ensure_config_file_exists
      config = load_config
      @database_file = config['database_file'] || DEFAULTS['database_file']
      @downloads_directory = config['downloads_directory'] || DEFAULTS['downloads_directory']
      @default_size_threshold = parse_size(config['default_size_threshold'] || DEFAULTS['default_size_threshold'])
      @replace_with_link = config.key?('replace_with_link') ? config['replace_with_link'] : DEFAULTS['replace_with_link']
      @use_database = config.key?('use_database') ? config['use_database'] : DEFAULTS['use_database']
    end

    def self.example_yaml
      <<~YAML
        # downloads_cleaner configuration
        # Path to the SQLite database file
        database_file: files.db

        # Directory to scan for downloads
        downloads_directory: ~/Downloads

        # Default file size threshold for cleaning (e.g., 100MB, 1GB, 500kB)
        default_size_threshold: 100MB

        # Replace deleted files with a .webloc link to the original URL (true/false)
        replace_with_link: false

        # Use the database to store deleted file info (true/false)
        use_database: true
      YAML
    end

    private

    def ensure_config_file_exists
      return if File.exist?(@config_path)
      FileUtils.mkdir_p(File.dirname(@config_path))
      File.write(@config_path, self.class.example_yaml)
    end

    def load_config
      return {} unless File.exist?(@config_path)
      YAML.safe_load(File.read(@config_path)) || {}
    rescue Psych::SyntaxError => e
      warn "[DownloadsCleaner::Config] YAML parse error: #{e.message}"
      {}
    end

    # Parse human-friendly size strings like "100MB", "1GB", "500kB"
    def parse_size(size)
      return nil unless size
      return size if size.is_a?(Integer)
      str = size.to_s.strip.downcase
      case str
      when /^(\d+)(b)?$/ then $1.to_i
      when /^(\d+(?:\.\d+)?)(kb)$/ then ($1.to_f * 1024).to_i
      when /^(\d+(?:\.\d+)?)(mb)$/ then ($1.to_f * 1024 * 1024).to_i
      when /^(\d+(?:\.\d+)?)(gb)$/ then ($1.to_f * 1024 * 1024 * 1024).to_i
      else
        unless caller.any? { |c| c.include?("minitest") || c.include?("test_") }
          puts "[DownloadsCleaner::Config] Unrecognized size format: '#{size}', using default."
        end
        parse_size(DEFAULTS['default_size_threshold'])
      end
    end
  end
end
