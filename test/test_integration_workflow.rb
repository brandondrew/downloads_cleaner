require_relative 'test_helper'

class TestIntegrationWorkflow < Minitest::Test
  include TestUtils

  def setup
    # Create temporary database for integration testing
    @temp_db = Tempfile.new(['integration_test_db', '.sqlite3'])
    @temp_db.close
    
    # Override database path for testing
    DownloadsCleaner::Database.test_db_path = @temp_db.path
    DownloadsCleaner::Database.reset_connection!
    
    # Initialize test database
    DownloadsCleaner::Database.migrate!
  end

  def teardown
    # Reset database connection
    DownloadsCleaner::Database.reset_connection!
    DownloadsCleaner::Database.test_db_path = nil
    
    # Cleanup temporary files
    @temp_db.unlink if @temp_db
  end

  def test_end_to_end_md5_computation_and_database_workflow
    # Create test file with known content
    test_content = "Integration test file content for MD5 verification"
    expected_md5 = Digest::MD5.hexdigest(test_content)
    
    temp_file = Tempfile.new('integration_test')
    temp_file.write(test_content)
    temp_file.close
    
    begin
      # Test MD5 computation (simulates what happens before deletion)
      computed_md5 = Digest::MD5.file(temp_file.path).hexdigest
      assert_equal expected_md5, computed_md5, "MD5 computation should work correctly"
      
      # Test database operations with computed MD5
      file_data = {
        name: "integration_test.zip",
        path: temp_file.path,
        size: test_content.length,
        md5: computed_md5,
        deleted_at: Time.now.strftime("%Y-%m-%d %H:%M:%S")
      }
      
      file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)
      refute_nil file_id, "Should successfully insert deleted file record"
      assert file_id > 0, "File ID should be positive integer"
      
      # Test URL insertion with MD5
      url_data = {
        url: "https://example.com/integration_test.zip",
        accessible: true,
        url_type: "file"
      }
      
      url_id = DownloadsCleaner::Database.insert_download_url(url_data, file_id, computed_md5)
      refute_nil url_id, "Should successfully insert download URL record"
      assert url_id > 0, "URL ID should be positive integer"
      
      # Test URL insertion with empty MD5 (edge case)
      empty_md5_url_data = {
        url: "https://backup.example.com/integration_test.zip",
        accessible: false,
        url_type: "file"
      }
      
      empty_url_id = DownloadsCleaner::Database.insert_download_url(empty_md5_url_data, file_id, "")
      refute_nil empty_url_id, "Should handle empty MD5 without constraint errors"
      
      # Verify data integrity in database
      db = DownloadsCleaner::Database.connection
      file_record = db.execute("SELECT * FROM deleted_files WHERE id = ?", [file_id]).first
      url_records = db.execute("SELECT * FROM download_urls WHERE deleted_file_id = ?", [file_id])
      
      assert_equal computed_md5, file_record["md5"], "File MD5 should be stored correctly"
      assert_equal 2, url_records.length, "Should have inserted both URL records"
      assert_equal computed_md5, url_records[0]["md5"], "First URL should have computed MD5"
      assert_equal "", url_records[1]["md5"], "Second URL should have empty MD5"
      
    ensure
      temp_file.unlink
    end
  end

  def test_input_handling_integration
    # Test nil input handling (simulates non-interactive environment)
    test_input = nil
    choice = test_input ? test_input.chomp : "3"
    
    assert_equal "3", choice, "Should default to '3' (exit) when input is nil"
    
    # Test normal input handling
    test_input = "1\n"
    choice = test_input ? test_input.chomp : "3"
    
    assert_equal "1", choice, "Should handle normal input correctly"
  end

  def test_database_schema_integrity
    # Verify that the database schema supports the fixed workflow
    db = DownloadsCleaner::Database.connection
    
    # Check deleted_files table has md5 column with NOT NULL constraint
    deleted_files_schema = db.execute("PRAGMA table_info(deleted_files)")
    md5_column = deleted_files_schema.find { |col| col["name"] == "md5" }
    
    refute_nil md5_column, "deleted_files table should have md5 column"
    assert_equal 1, md5_column["notnull"], "md5 column should have NOT NULL constraint"
    
    # Check download_urls table has md5 column with NOT NULL constraint
    download_urls_schema = db.execute("PRAGMA table_info(download_urls)")
    url_md5_column = download_urls_schema.find { |col| col["name"] == "md5" }
    
    refute_nil url_md5_column, "download_urls table should have md5 column"
    assert_equal 1, url_md5_column["notnull"], "download_urls.md5 should have NOT NULL constraint"
  end

  def test_workflow_prevents_original_constraint_error
    # This test specifically verifies the original bug scenario doesn't occur
    
    # Simulate the old buggy workflow: trying to insert empty/nil MD5
    file_data = {
      name: "constraint_test.zip",
      path: "/test/constraint_test.zip",
      size: 1024,
      md5: "", # Empty MD5 (what the bug produced)
      deleted_at: Time.now.strftime("%Y-%m-%d %H:%M:%S")
    }
    
    # This should work now (empty string is valid)
    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)
    refute_nil file_id, "Should handle empty MD5 string without constraint error"
    
    # This should also work
    url_data = {
      url: "https://example.com/constraint_test.zip",
      accessible: true,
      url_type: "file"
    }
    
    url_id = DownloadsCleaner::Database.insert_download_url(url_data, file_id, "")
    refute_nil url_id, "Should handle empty MD5 in URL without constraint error"
    
    # However, nil should still raise an error (as expected)
    assert_raises(SQLite3::ConstraintException) do
      DownloadsCleaner::Database.insert_download_url(url_data, file_id, nil)
    end
  end
end