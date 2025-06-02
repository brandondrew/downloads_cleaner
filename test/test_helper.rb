require 'minitest/autorun'
require 'minitest/pride' # For colorful test output
require 'webmock/minitest'
require 'stringio'
require 'tempfile'
require 'fileutils'

# Path to the main script file
require_relative '../downloads_manager'

# Configure WebMock to disable external requests during tests
WebMock.disable_net_connect!(allow_localhost: true)

# Test utilities
module TestUtils
  # Capture stdout during test execution
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
  
  # Create a temporary directory for test files
  def create_temp_dir
    dir = Dir.mktmpdir('downloads_manager_test')
    yield(dir) if block_given?
    dir
  end
  
  # Create a test file with specified size
  def create_test_file(dir, name, size_bytes)
    path = File.join(dir, name)
    File.open(path, 'wb') do |f|
      # Write in chunks to avoid memory issues with large files
      chunk_size = [1024 * 1024, size_bytes].min # 1MB or file size, whichever is smaller
      (size_bytes / chunk_size).times { f.write('0' * chunk_size) }
      f.write('0' * (size_bytes % chunk_size)) if size_bytes % chunk_size > 0
    end
    path
  end
  
  # Create a URL file (Windows-style Internet shortcut)
  def create_url_file(dir, name, url)
    path = File.join(dir, "#{name}.url")
    File.write(path, "URL=#{url}")
    path
  end
end

# Mock classes for testing
module Mocks
  # Mock FileSystem class
  class MockFileSystem
    class << self
      attr_accessor :files, :directories, :file_sizes, :file_contents
      
      def reset!
        @files = {}
        @directories = []
        @file_sizes = {}
        @file_contents = {}
        @deleted_files = []
        @written_files = {}
      end
      
      def downloads_path
        "/mock/downloads"
      end
      
      def file_exists?(path)
        @files[path] || false
      end
      
      def directory_exists?(path)
        @directories.include?(path)
      end
      
      def file_size(path)
        @file_sizes[path] || 0
      end
      
      def delete_file(path)
        @deleted_files ||= []
        @deleted_files << path
        @files.delete(path)
      end
      
      def get_files_in_directory(path)
        @files.keys.select { |f| f.start_with?("#{path}/") }
      end
      
      def basename(path, ext = nil)
        base = File.basename(path)
        ext ? base.chomp(ext) : base
      end
      
      def write_file(path, content)
        @written_files ||= {}
        @written_files[path] = content
      end
      
      def read_file(path)
        @file_contents[path] || ""
      end
      
      def deleted_files
        @deleted_files || []
      end
      
      def written_files
        @written_files || {}
      end
    end
  end
  
  # Mock UrlChecker class
  class MockUrlChecker
    class << self
      attr_accessor :accessible_urls
      
      def reset!
        @accessible_urls = {}
      end
      
      def accessible?(url)
        @accessible_urls[url] || false
      end
    end
  end
end

# Initialize mock state before each test
Minitest.after_run do
  Mocks::MockFileSystem.reset!
  Mocks::MockUrlChecker.reset!
end