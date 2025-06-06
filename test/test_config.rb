# frozen_string_literal: true
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require_relative '../lib/downloads_cleaner/config'

class TestDownloadsCleanerConfig < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, 'config.yaml')
    @env_home = ENV['HOME']
    ENV['HOME'] = @tmpdir
    ENV.delete('CLEANER_HOME')
  end

  def teardown
    ENV['HOME'] = @env_home
    FileUtils.remove_entry(@tmpdir)
  end

  def test_creates_config_file_with_defaults
    FileUtils.rm_f(@config_path)
    config = DownloadsCleaner::Config.new(@config_path)
    assert File.exist?(@config_path), 'Config file should be created if missing'
    yaml = YAML.safe_load(File.read(@config_path))
    assert_equal 'files.db', yaml['database_file']
    assert_equal File.join(@tmpdir, 'Downloads'), File.expand_path(yaml['downloads_directory'].gsub('~', @tmpdir))
    assert_equal '100MB', yaml['default_size_threshold']
  end

  def test_reads_and_parses_human_friendly_size
    File.write(@config_path, DownloadsCleaner::Config.example_yaml)
    config = DownloadsCleaner::Config.new(@config_path)
    assert_equal 100 * 1024 * 1024, config.default_size_threshold
  end

  def test_reads_custom_values
    yaml = {
      'database_file' => '/tmp/special.db',
      'downloads_directory' => '/tmp/downloads',
      'default_size_threshold' => '2GB'
    }
    File.write(@config_path, yaml.to_yaml)
    config = DownloadsCleaner::Config.new(@config_path)
    assert_equal '/tmp/special.db', config.database_file
    assert_equal '/tmp/downloads', config.downloads_directory
    assert_equal 2 * 1024 * 1024 * 1024, config.default_size_threshold
  end

  def test_invalid_size_falls_back_to_default
    File.write(@config_path, { 'default_size_threshold' => 'nonsense' }.to_yaml)
    config = DownloadsCleaner::Config.new(@config_path)
    assert_equal 100 * 1024 * 1024, config.default_size_threshold
  end
end
