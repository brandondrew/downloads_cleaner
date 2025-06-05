require_relative 'test_helper'
require 'digest'
require 'tempfile'
require 'fileutils'

class TestDeletionMd5Fixes < Minitest::Test
  include TestUtils

  def setup
    @temp_dir = create_temp_dir
    @test_file_path = File.join(@temp_dir, 'test_file.zip')
    @test_file_content = 'test content for md5 calculation'
    File.write(@test_file_path, @test_file_content)
    
    # Calculate expected MD5
    @expected_md5 = Digest::MD5.hexdigest(@test_file_content)
    
    # Set up in-memory database to prevent pollution
    DownloadsCleaner::Database.test_db_path = ":memory:"
    DownloadsCleaner::Database.reset_connection!
    
    # Mock filesystem that tracks state
    @mock_filesystem = Class.new do
      attr_accessor :deleted_files, :written_files, :files, :file_sizes
      
      def initialize
        @deleted_files = []
        @written_files = {}
        @files = {}
        @file_sizes = {}
      end
      
      def downloads_path
        "/mock/downloads"
      end
      
      def file_exists?(path)
        @files.has_key?(path) && @files[path]
      end
      
      def directory_exists?(path)
        path == downloads_path
      end
      
      def file_size(path)
        @file_sizes[path] || 0
      end
      
      def delete_file(path)
        @deleted_files << path
        @files[path] = false  # Mark as deleted
      end
      
      def get_files_in_directory(path)
        @files.keys.select { |f| f.start_with?("#{path}/") && @files[f] }
      end
      
      def basename(path, ext = nil)
        base = File.basename(path)
        ext ? base.chomp(ext) : base
      end
      
      def write_file(path, content)
        @written_files[path] = content
      end
      
      def read_file(path)
        "sample content"
      end
    end.new
    
    # Setup mock files
    @test_file_path_mock = "/mock/downloads/test_file.zip"
    @mock_filesystem.files[@test_file_path_mock] = true
    @mock_filesystem.file_sizes[@test_file_path_mock] = 150 * 1024 * 1024  # 150MB
    
    @mock_url_checker = Class.new do
      def self.accessible?(url)
        true
      end
    end
    
    @cleaner = DownloadsCleaner::Cleaner.new(
      filesystem: @mock_filesystem,
      url_checker: @mock_url_checker,
      threshold: 100 * 1024 * 1024  # 100MB
    )
    
    # Setup retrievable files for testing
    @cleaner.instance_variable_set(:@retrievable_files, [
      {
        name: "test_file.zip",
        path: @test_file_path_mock,
        size: 150 * 1024 * 1024,
        download_urls: [
          { url: "https://example.com/test_file.zip", accessible: true, url_type: "file" }
        ]
      }
    ])
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    
    # Reset database connection
    DownloadsCleaner::Database.reset_connection!
    DownloadsCleaner::Database.test_db_path = nil
  end

  def test_md5_computation_before_deletion_in_delete_all_files
    # Mock the database to capture what gets inserted
    database_calls = []
    
    DownloadsCleaner::Database.stub :migrate!, nil do
      DownloadsCleaner::Database.stub :insert_deleted_file, ->(data) {
        database_calls << [:insert_deleted_file, data]
        1  # Return mock file ID
      } do
        DownloadsCleaner::Database.stub :insert_download_url, ->(url_data, file_id, md5) {
          database_calls << [:insert_download_url, url_data, file_id, md5]
        } do
          # Override Digest::MD5.file to simulate real MD5 calculation
          Digest::MD5.stub :file, ->(path) {
            mock_digest = Object.new
            def mock_digest.hexdigest
              "mock_md5_hash_123456"
            end
            mock_digest
          } do
            # Simulate stdin input for choice "d" (delete)
            $stdin.stub :gets, "d\n" do
              capture_stdout do
                result = @cleaner.send(:delete_all_files)
                assert_equal :exit, result
              end
            end
          end
        end
      end
    end
    
    # Verify file was marked as deleted
    assert_includes @mock_filesystem.deleted_files, @test_file_path_mock
    
    # Verify database calls were made with correct MD5
    file_insert_call = database_calls.find { |call| call[0] == :insert_deleted_file }
    refute_nil file_insert_call, "Should have called insert_deleted_file"
    assert_equal "mock_md5_hash_123456", file_insert_call[1][:md5]
    
    url_insert_call = database_calls.find { |call| call[0] == :insert_download_url }
    refute_nil url_insert_call, "Should have called insert_download_url"
    assert_equal "mock_md5_hash_123456", url_insert_call[3]  # MD5 parameter
  end

  def test_md5_computation_before_deletion_in_delete_files_individually
    database_calls = []
    
    DownloadsCleaner::Database.stub :migrate!, nil do
      DownloadsCleaner::Database.stub :insert_deleted_file, ->(data) {
        database_calls << [:insert_deleted_file, data]
        1
      } do
        DownloadsCleaner::Database.stub :insert_download_url, ->(url_data, file_id, md5) {
          database_calls << [:insert_download_url, url_data, file_id, md5]
        } do
          Digest::MD5.stub :file, ->(path) {
            mock_digest = Object.new
            def mock_digest.hexdigest
              "individual_md5_hash_789"
            end
            mock_digest
          } do
            # Simulate stdin input: "d" to delete the file
            inputs = ["d\n"]
            input_index = 0
            
            $stdin.stub :gets, -> {
              result = inputs[input_index]
              input_index += 1
              result
            } do
              capture_stdout do
                result = @cleaner.send(:delete_files_individually)
                assert_equal :exit, result
              end
            end
          end
        end
      end
    end
    
    # Verify file was deleted
    assert_includes @mock_filesystem.deleted_files, @test_file_path_mock
    
    # Verify MD5 was computed and stored correctly
    file_insert_call = database_calls.find { |call| call[0] == :insert_deleted_file }
    assert_equal "individual_md5_hash_789", file_insert_call[1][:md5]
    
    url_insert_call = database_calls.find { |call| call[0] == :insert_download_url }
    assert_equal "individual_md5_hash_789", url_insert_call[3]
  end

  def test_md5_handles_file_access_errors_gracefully
    database_calls = []
    
    DownloadsCleaner::Database.stub :migrate!, nil do
      DownloadsCleaner::Database.stub :insert_deleted_file, ->(data) {
        database_calls << [:insert_deleted_file, data]
        1
      } do
        DownloadsCleaner::Database.stub :insert_download_url, ->(url_data, file_id, md5) {
          database_calls << [:insert_download_url, url_data, file_id, md5]
        } do
          # Simulate MD5 computation error
          Digest::MD5.stub :file, ->(path) {
            raise Errno::EACCES, "Permission denied"
          } do
            $stdin.stub :gets, "1\n" do
              output = capture_stdout do
                @cleaner.send(:delete_all_files)
              end
              
              # Should contain warning about MD5 computation failure
              assert_includes output, "Warning: Could not compute MD5"
            end
          end
        end
      end
    end
    
    # Verify that empty MD5 was used when computation failed
    file_insert_call = database_calls.find { |call| call[0] == :insert_deleted_file }
    assert_equal "", file_insert_call[1][:md5]
  end

  def test_md5_handles_nonexistent_files_gracefully
    # Make file not exist
    @mock_filesystem.files[@test_file_path_mock] = false
    
    database_calls = []
    
    DownloadsCleaner::Database.stub :migrate!, nil do
      DownloadsCleaner::Database.stub :insert_deleted_file, ->(data) {
        database_calls << [:insert_deleted_file, data]
        1
      } do
        DownloadsCleaner::Database.stub :insert_download_url, ->(url_data, file_id, md5) {
          database_calls << [:insert_download_url, url_data, file_id, md5]
        } do
          $stdin.stub :gets, "1\n" do
            capture_stdout do
              @cleaner.send(:delete_all_files)
            end
          end
        end
      end
    end
    
    # Verify that empty MD5 was used for nonexistent file
    file_insert_call = database_calls.find { |call| call[0] == :insert_deleted_file }
    assert_equal "", file_insert_call[1][:md5]
  end

  def test_stdin_nil_handling_in_prompt_for_deletion
    # Simulate stdin returning nil (non-interactive environment)
    $stdin.stub :gets, nil do
      output = capture_stdout do
        result = @cleaner.send(:prompt_for_deletion)
        assert_equal :exit, result
      end
      
      # Should default to option 3 (exit) when stdin is nil
      assert_includes output, "No files deleted"
    end
  end

  def test_stdin_nil_handling_in_delete_files_individually
    # Mock stdin to return nil
    $stdin.stub :gets, nil do
      output = capture_stdout do
        result = @cleaner.send(:delete_files_individually)
        assert_equal :exit, result
      end
      
      # Should default to "n" (no) for individual file deletion
      assert_includes output, "Kept test_file.zip"
    end
  end

  def test_save_deleted_files_list_uses_precomputed_md5
    deleted_files = [
      {
        name: "test_file.zip",
        path: @test_file_path_mock,
        size: 150 * 1024 * 1024,
        md5: "precomputed_md5_hash",  # Pre-computed MD5
        download_urls: [
          { url: "https://example.com/test_file.zip", accessible: true, url_type: "file" }
        ]
      }
    ]
    
    database_calls = []
    
    DownloadsCleaner::Database.stub :migrate!, nil do
      DownloadsCleaner::Database.stub :insert_deleted_file, ->(data) {
        database_calls << [:insert_deleted_file, data]
        1
      } do
        DownloadsCleaner::Database.stub :insert_download_url, ->(url_data, file_id, md5) {
          database_calls << [:insert_download_url, url_data, file_id, md5]
        } do
          capture_stdout do
            @cleaner.send(:save_deleted_files_list, deleted_files)
          end
        end
      end
    end
    
    # Verify the pre-computed MD5 was used
    file_insert_call = database_calls.find { |call| call[0] == :insert_deleted_file }
    assert_equal "precomputed_md5_hash", file_insert_call[1][:md5]
    
    url_insert_call = database_calls.find { |call| call[0] == :insert_download_url }
    assert_equal "precomputed_md5_hash", url_insert_call[3]
  end

  def test_save_deleted_files_list_handles_missing_md5
    deleted_files = [
      {
        name: "test_file.zip",
        path: @test_file_path_mock,
        size: 150 * 1024 * 1024,
        # No md5 key - should default to empty string
        download_urls: [
          { url: "https://example.com/test_file.zip", accessible: true, url_type: "file" }
        ]
      }
    ]
    
    database_calls = []
    
    DownloadsCleaner::Database.stub :migrate!, nil do
      DownloadsCleaner::Database.stub :insert_deleted_file, ->(data) {
        database_calls << [:insert_deleted_file, data]
        1
      } do
        DownloadsCleaner::Database.stub :insert_download_url, ->(url_data, file_id, md5) {
          database_calls << [:insert_download_url, url_data, file_id, md5]
        } do
          capture_stdout do
            @cleaner.send(:save_deleted_files_list, deleted_files)
          end
        end
      end
    end
    
    # Verify empty string is used when md5 is missing
    file_insert_call = database_calls.find { |call| call[0] == :insert_deleted_file }
    assert_equal "", file_insert_call[1][:md5]
    
    url_insert_call = database_calls.find { |call| call[0] == :insert_download_url }
    assert_equal "", url_insert_call[3]
  end

  def test_real_md5_computation_with_actual_file
    # Test with real file to ensure MD5 computation actually works
    test_content = "This is test content for MD5 computation"
    expected_md5 = Digest::MD5.hexdigest(test_content)
    
    # Create actual temporary file
    temp_file = Tempfile.new('md5_test')
    temp_file.write(test_content)
    temp_file.close
    
    begin
      # Test actual MD5 computation
      computed_md5 = Digest::MD5.file(temp_file.path).hexdigest
      assert_equal expected_md5, computed_md5
      
      # Verify our test setup is correct
      refute_empty computed_md5
      assert_equal 32, computed_md5.length  # MD5 hash should be 32 characters
    ensure
      temp_file.unlink
    end
  end
end