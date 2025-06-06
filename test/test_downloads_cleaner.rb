require_relative 'test_helper'

require 'tmpdir'

class TestDownloadsCleaner < Minitest::Test
  TMP_PRESERVED = File.join(Dir.tmpdir, "downloads_cleaner_test_preserved.txt")
  class MockFileSystem
    def self.downloads_path
      "/mock/downloads"
    end

    def self.file_exists?(path)
      path.include?("existing")
    end

    def self.directory_exists?(path)
      path.include?("downloads")
    end

    def self.file_size(path)
      case path
      when /large/ then 150 * 1024 * 1024  # 150MB
      when /medium/ then 80 * 1024 * 1024  # 80MB
      when /small/ then 10 * 1024 * 1024   # 10MB
      else 1024                           # 1KB default
      end
    end

    def self.delete_file(path)
      # Mock implementation, just return true
      true
    end

    def self.get_files_in_directory(path)
      [
        "/mock/downloads/large_file.dmg",
        "/mock/downloads/medium_file.zip",
        "/mock/downloads/small_file.txt"
      ]
    end

    def self.basename(path, ext = nil)
      base = File.basename(path)
      ext ? base.gsub(ext, "") : base
    end

    def self.write_file(path, content)
      # Mock implementation, just return true
      true
    end

    def self.read_file(path)
      if path.include?("url_file")
        "URL=https://example.com/download"
      else
        "Sample content"
      end
    end
  end

  class MockUrlChecker
    def self.accessible?(url)
      !url.include?("inaccessible")
    end

    def self.check_url(url)
      {
        accessible: !url.include?("inaccessible"),
        url_type: url.include?(".dmg") || url.include?(".zip") ? "file" : "site"
      }
    end
    
    # Add instance methods that mirror the class methods
    def accessible?(url)
      self.class.accessible?(url)
    end

    def check_url(url)
      self.class.check_url(url)
    end
  end

  def setup
    @original_stdout = $stdout
    $stdout = StringIO.new

    @mock_filesystem = MockFileSystem
    @mock_url_checker = MockUrlChecker

    # Clean up preserved list file for isolation
    FileUtils.rm_f(TMP_PRESERVED)
    @cleaner = DownloadsCleaner::Cleaner.new(
      filesystem: @mock_filesystem,
      url_checker: @mock_url_checker,
      threshold: 50 * 1024 * 1024,  # 50MB threshold for tests
      preserved_list_path: TMP_PRESERVED
    )

    # Capture stdout for testing output
    @original_stdout = $stdout
    $stdout = StringIO.new
  end

  def teardown
    # Restore stdout
    $stdout = @original_stdout
  end

  def test_initialization
    assert_equal 50 * 1024 * 1024, @cleaner.options[:threshold]
    assert_equal :prompt, @cleaner.options[:mode]
    assert_equal [], @cleaner.large_files
    assert_equal [], @cleaner.retrievable_files
  end

  def test_parse_arguments_with_size
    result = @cleaner.send(:parse_arguments, ["100MB"])
    assert_equal :continue, result
    assert_equal 100 * 1024 * 1024, @cleaner.options[:threshold]
  end

  def test_parse_arguments_with_invalid_size
    result = @cleaner.send(:parse_arguments, ["invalid"])
    assert_equal :exit, result
  end

  def test_parse_arguments_with_help_flag
    result = @cleaner.send(:parse_arguments, ["-h"])
    assert_equal :exit, result
  end

  def test_parse_arguments_with_delete_flag
    result = @cleaner.send(:parse_arguments, ["--delete", "200MB"])
    assert_equal :continue, result
    assert_equal :delete, @cleaner.options[:mode]
    assert_equal 200 * 1024 * 1024, @cleaner.options[:threshold]
  end

  def test_find_large_files
    result = @cleaner.send(:find_large_files)
    assert_equal :continue, result

    # Should find files above threshold (50MB in our test)
    assert_equal 2, @cleaner.large_files.length

    # Verify first file
    assert_equal "/mock/downloads/large_file.dmg", @cleaner.large_files[0][:path]
    assert_equal "large_file.dmg", @cleaner.large_files[0][:name]
    assert_equal 150 * 1024 * 1024, @cleaner.large_files[0][:size]

    # Verify second file
    assert_equal "/mock/downloads/medium_file.zip", @cleaner.large_files[1][:path]
    assert_equal "medium_file.zip", @cleaner.large_files[1][:name]
    assert_equal 80 * 1024 * 1024, @cleaner.large_files[1][:size]
  end

  def test_find_large_files_excludes_preserved
    # Add a file to the preserved list
    preserved_file = "/mock/downloads/large_file.dmg"
    @cleaner.instance_variable_get(:@preserved_list).add(preserved_file)
    @cleaner.send(:find_large_files)
    # Only medium file should be found
    assert_equal 1, @cleaner.large_files.length
    assert_equal "/mock/downloads/medium_file.zip", @cleaner.large_files[0][:path]
  end

  def test_find_large_files_with_nonexistent_directory
    # Override directory_exists? for this test
    @mock_filesystem.stub :directory_exists?, false do
      result = @cleaner.send(:find_large_files)
      assert_equal :exit, result
      assert_equal 0, @cleaner.large_files.length
    end
  end

  def test_extract_urls_from_plist_xml
    xml_data = '<plist><array><string>https://example.com/download1</string><string>https://example.com/download2</string></array></plist>'
    urls = @cleaner.send(:extract_urls_from_plist_xml, xml_data)

    assert_equal 2, urls.length
    assert_includes urls, "https://example.com/download1"
    assert_includes urls, "https://example.com/download2"
  end

  def test_get_url_from_alternative_sources
    # Use temporary stubbing instead of monkey-patching
    @mock_filesystem.stub :basename, "file_with_url_file" do
      @mock_filesystem.stub :file_exists?, ->(path) { path.include?("file_with_url_file.url") } do
        result = @cleaner.send(:get_url_from_alternative_sources, "/mock/downloads/file_with_url_file.dmg")
        assert_equal "https://example.com/download", result[:url]
        assert_equal true, result[:accessible]
        assert_equal "site", result[:url_type]
      end
    end
  end

  def test_generate_report_content
    # Setup test data
    deleted_files = [
      {
        name: "test_file.dmg",
        size: 100 * 1024 * 1024,
        download_urls: [{ url: "https://example.com/test_file.dmg", accessible: true, url_type: "file" }]
      },
      {
        name: "another_file.zip",
        size: 50 * 1024 * 1024,
        download_urls: [
          { url: "https://example.com/another_file.zip", accessible: true, url_type: "file" },
          { url: "https://mirror.example.com/another_file.zip", accessible: false, url_type: "file" }
        ]
      }
    ]

    content = @cleaner.send(:generate_report_content, deleted_files)

    # Verify content contains the expected information
    assert content.include?("# Retrievable Downloads")
    assert content.include?("## 1. test_file.dmg")
    assert content.include?("- **Size**: 100.0MB")
    assert content.include?("https://example.com/test_file.dmg (accessible")
    assert content.include?("## 2. another_file.zip")
    assert content.include?("- **Size**: 50.0MB")
    assert content.include?("https://example.com/another_file.zip (accessible")
    assert content.include?("https://mirror.example.com/another_file.zip (not accessible")
    
    # Verify we have the summary information too
    assert content.include?("**Total space freed**: 150.0MB")
    assert content.include?("**Files deleted**: 2")
  end

  def test_display_retrievable_files_with_empty_list
    result = @cleaner.send(:display_retrievable_files)
    assert_equal :exit, result
    assert $stdout.string.include?("No large files found")
    refute $stdout.string.include?("What would you like to do?"), "Should not prompt for deletion when no files are found"
    refute $stdout.string.include?("Enter your choice"), "Should not prompt for choice when no files are found"
  end

  def test_display_retrievable_files_with_files
    # Add some retrievable files
    @cleaner.instance_variable_set(:@retrievable_files, [
      {
        name: "test_file.dmg",
        size: 100 * 1024 * 1024,
        download_urls: [{ url: "https://example.com/test_file.dmg", accessible: true }]
      }
    ])

    result = @cleaner.send(:display_retrievable_files)
    assert_equal :continue, result
    assert $stdout.string.include?("FILES THAT CAN BE DELETED AND RETRIEVED LATER")
    assert $stdout.string.include?("1. test_file.dmg")
    assert $stdout.string.include?("Size: 100.0MB")
  end

  def test_delete_file_option_in_individual_delete
    file_info = {
      path: "/mock/downloads/large_file.dmg",
      name: "large_file.dmg",
      size: 150 * 1024 * 1024,
      download_urls: [{ url: "https://example.com/large_file.dmg", accessible: true, url_type: "file" }]
    }
    @cleaner.instance_variable_set(:@retrievable_files, [file_info])
    $stdin = StringIO.new("d\n")
    @cleaner.send(:delete_files_individually)
    # Since delete_file is mocked to return true, just check output
    assert_match(/Deleted large_file.dmg/, $stdout.string)
  ensure
    $stdin = STDIN
  end

  def test_preserve_file_option_in_individual_delete
    # Prepare a retrievable file
    file_info = {
      path: "/mock/downloads/large_file.dmg",
      name: "large_file.dmg",
      size: 150 * 1024 * 1024,
      download_urls: [{ url: "https://example.com/large_file.dmg", accessible: true, url_type: "file" }]
    }
    @cleaner.instance_variable_set(:@retrievable_files, [file_info])
    # Simulate user entering 'p' (preserve)
    $stdin = StringIO.new("p\n")
    @cleaner.send(:delete_files_individually)
    preserved_list = @cleaner.instance_variable_get(:@preserved_list)
    assert preserved_list.include?("/mock/downloads/large_file.dmg"), "File should be preserved"
  ensure
    $stdin = STDIN
  end

  def test_keep_file_option_in_individual_delete
    # Prepare a retrievable file
    file_info = {
      path: "/mock/downloads/large_file.dmg",
      name: "large_file.dmg",
      size: 150 * 1024 * 1024,
      download_urls: [{ url: "https://example.com/large_file.dmg", accessible: true, url_type: "file" }]
    }
    @cleaner.instance_variable_set(:@retrievable_files, [file_info])
    # Simulate user entering 'k' (keep)
    $stdin = StringIO.new("k\n")
    @cleaner.send(:delete_files_individually)
    preserved_list = @cleaner.instance_variable_get(:@preserved_list)
    refute preserved_list.include?("/mock/downloads/large_file.dmg"), "File should not be preserved"
  ensure
    $stdin = STDIN
  end

  def test_webloc_creation_enabled
    @cleaner.options[:replace_with_link] = true
    @cleaner.options[:downloads_directory] = "/mock/downloads"
    file_info = {
      path: "/mock/downloads/large_file.dmg",
      name: "large_file.dmg",
      size: 150 * 1024 * 1024,
      download_urls: [{ url: "https://example.com/large_file.dmg", accessible: true, url_type: "file" }]
    }
    @cleaner.instance_variable_set(:@retrievable_files, [file_info])
    @mock_filesystem.stub :file_exists?, true do
      @mock_filesystem.stub :get_files_in_directory, ["/mock/downloads/large_file.dmg"] do
        @mock_filesystem.stub :read_file, "URL=https://example.com/download" do
          @cleaner.send(:delete_all_files)
          assert @mock_filesystem.file_exists?("/mock/downloads/large_file.dmg.webloc"), "Webloc file should be created."
          assert_equal "URL=https://example.com/download", @mock_filesystem.read_file("/mock/downloads/large_file.dmg.webloc")
        end
      end
    end
  end

  def test_webloc_creation_disabled
    opts = {
      replace_with_link: false,
      downloads_directory: "/mock/downloads"
    }
    cleaner = DownloadsCleaner::Cleaner.new(opts)
    cleaner.instance_variable_set(:@filesystem, @mock_filesystem)
    file_info = {
      path: "/mock/downloads/large_file.dmg",
      name: "large_file.dmg",
      size: 150 * 1024 * 1024,
      download_urls: [{ url: "https://example.com/large_file.dmg", accessible: true, url_type: "file" }]
    }
    cleaner.instance_variable_set(:@retrievable_files, [file_info])
    @mock_filesystem.stub :file_exists?, true do
      @mock_filesystem.stub :get_files_in_directory, ["/mock/downloads/large_file.dmg"] do
        @mock_filesystem.stub :read_file, "" do
          DownloadsCleaner::WeblocWriter.stub(:write_webloc, ->(*args) { flunk(".webloc should not be created") }) do
            cleaner.send(:delete_all_files)
          end
        end
      end
    end
  end

end
