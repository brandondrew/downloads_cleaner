require_relative 'test_helper'
require 'tempfile'
require 'fileutils'

class TestDatabaseMd5Constraints < Minitest::Test
  def setup
    # Create a temporary database file
    @temp_db_file = Tempfile.new(['test_db', '.sqlite3'])
    @temp_db_file.close
    
    # Override the database path for testing
    DownloadsCleaner::Database.test_db_path = @temp_db_file.path
    DownloadsCleaner::Database.reset_connection!
    
    # Initialize the test database
    DownloadsCleaner::Database.migrate!
  end

  def teardown
    # Reset database connection
    DownloadsCleaner::Database.reset_connection!
    DownloadsCleaner::Database.test_db_path = nil
    
    # Clean up temporary file
    @temp_db_file.unlink if @temp_db_file
  end

  def test_insert_deleted_file_with_valid_md5
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      deleted_at: "2024-06-04 20:00:00"
    }

    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)
    
    refute_nil file_id
    assert file_id > 0
    
    # Verify the record was inserted correctly
    db = DownloadsCleaner::Database.connection
    result = db.execute("SELECT * FROM deleted_files WHERE id = ?", [file_id]).first
    
    assert_equal "test_file.zip", result["name"]
    assert_equal "/test/path/test_file.zip", result["path"]
    assert_equal 1024000, result["size"]
    assert_equal "d41d8cd98f00b204e9800998ecf8427e", result["md5"]
  end

  def test_insert_deleted_file_with_empty_md5
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "",
      deleted_at: "2024-06-04 20:00:00"
    }

    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)
    
    refute_nil file_id
    assert file_id > 0
    
    # Verify the record was inserted with empty MD5
    db = DownloadsCleaner::Database.connection
    result = db.execute("SELECT * FROM deleted_files WHERE id = ?", [file_id]).first
    
    assert_equal "", result["md5"]
  end

  def test_insert_download_url_with_valid_md5
    # First insert a deleted file
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "valid_md5_hash_12345",
      deleted_at: "2024-06-04 20:00:00"
    }
    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)

    # Now insert a download URL
    url_data = {
      url: "https://example.com/test_file.zip",
      accessible: true,
      url_type: "file"
    }
    
    url_id = DownloadsCleaner::Database.insert_download_url(url_data, file_id, "valid_md5_hash_12345")
    
    refute_nil url_id
    assert url_id > 0
    
    # Verify the URL record was inserted correctly
    db = DownloadsCleaner::Database.connection
    result = db.execute("SELECT * FROM download_urls WHERE id = ?", [url_id]).first
    
    assert_equal file_id, result["deleted_file_id"]
    assert_equal "https://example.com/test_file.zip", result["url"]
    assert_equal "valid_md5_hash_12345", result["md5"]
    assert_equal 1, result["accessible"]
    assert_equal "file", result["url_type"]
  end

  def test_insert_download_url_with_empty_md5
    # First insert a deleted file
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "",
      deleted_at: "2024-06-04 20:00:00"
    }
    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)

    # Now insert a download URL with empty MD5
    url_data = {
      url: "https://example.com/test_file.zip",
      accessible: true,
      url_type: "file"
    }
    
    url_id = DownloadsCleaner::Database.insert_download_url(url_data, file_id, "")
    
    refute_nil url_id
    assert url_id > 0
    
    # Verify the URL record was inserted with empty MD5
    db = DownloadsCleaner::Database.connection
    result = db.execute("SELECT * FROM download_urls WHERE id = ?", [url_id]).first
    
    assert_equal "", result["md5"]
  end

  def test_insert_download_url_prevents_null_md5
    # First insert a deleted file
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "some_hash",
      deleted_at: "2024-06-04 20:00:00"
    }
    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)

    # Try to insert a download URL with nil MD5 - should raise an error
    url_data = {
      url: "https://example.com/test_file.zip",
      accessible: true,
      url_type: "file"
    }
    
    assert_raises(SQLite3::ConstraintException) do
      DownloadsCleaner::Database.insert_download_url(url_data, file_id, nil)
    end
  end

  def test_database_schema_enforces_md5_not_null
    # Test that the database schema actually enforces NOT NULL on md5 column
    db = DownloadsCleaner::Database.connection
    
    # Verify download_urls table schema
    schema = db.execute("PRAGMA table_info(download_urls)")
    md5_column = schema.find { |col| col["name"] == "md5" }
    
    refute_nil md5_column, "md5 column should exist in download_urls table"
    assert_equal 1, md5_column["notnull"], "md5 column should have NOT NULL constraint"
  end

  def test_database_migration_adds_md5_column
    # This test verifies that the migration correctly adds the md5 column
    db = DownloadsCleaner::Database.connection
    
    # Check that both tables have md5 columns
    deleted_files_schema = db.execute("PRAGMA table_info(deleted_files)")
    download_urls_schema = db.execute("PRAGMA table_info(download_urls)")
    
    deleted_files_md5 = deleted_files_schema.find { |col| col["name"] == "md5" }
    download_urls_md5 = download_urls_schema.find { |col| col["name"] == "md5" }
    
    refute_nil deleted_files_md5, "deleted_files table should have md5 column"
    refute_nil download_urls_md5, "download_urls table should have md5 column"
    
    # Verify NOT NULL constraints
    assert_equal 1, deleted_files_md5["notnull"], "deleted_files.md5 should be NOT NULL"
    assert_equal 1, download_urls_md5["notnull"], "download_urls.md5 should be NOT NULL"
  end

  def test_unique_constraint_on_deleted_file_id_and_url
    # Insert a deleted file
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "test_md5_hash",
      deleted_at: "2024-06-04 20:00:00"
    }
    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)

    # Insert first URL
    url_data = {
      url: "https://example.com/test_file.zip",
      accessible: true,
      url_type: "file"
    }
    
    first_url_id = DownloadsCleaner::Database.insert_download_url(url_data, file_id, "test_md5_hash")
    refute_nil first_url_id

    # Try to insert the same URL for the same file - should be silently ignored
    second_url_id = DownloadsCleaner::Database.insert_download_url(url_data, file_id, "test_md5_hash")
    assert_nil second_url_id, "Duplicate URL insertion should return nil"
  end

  def test_foreign_key_constraint
    # Try to insert a download URL with non-existent deleted_file_id
    url_data = {
      url: "https://example.com/test_file.zip",
      accessible: true,
      url_type: "file"
    }
    
    # This should raise a foreign key constraint error
    assert_raises(SQLite3::ConstraintException) do
      DownloadsCleaner::Database.insert_download_url(url_data, 99999, "some_md5_hash")
    end
  end

  def test_cascade_delete_works
    # Insert a deleted file
    file_data = {
      name: "test_file.zip",
      path: "/test/path/test_file.zip",
      size: 1024000,
      md5: "test_md5_hash",
      deleted_at: "2024-06-04 20:00:00"
    }
    file_id = DownloadsCleaner::Database.insert_deleted_file(file_data)

    # Insert multiple URLs for this file
    url_data1 = { url: "https://example.com/test_file.zip", accessible: true, url_type: "file" }
    url_data2 = { url: "https://mirror.com/test_file.zip", accessible: true, url_type: "file" }
    
    DownloadsCleaner::Database.insert_download_url(url_data1, file_id, "test_md5_hash")
    DownloadsCleaner::Database.insert_download_url(url_data2, file_id, "test_md5_hash")

    # Verify URLs were inserted
    db = DownloadsCleaner::Database.connection
    urls_before_result = db.execute("SELECT COUNT(*) FROM download_urls WHERE deleted_file_id = ?", [file_id])
    urls_before = urls_before_result.first["COUNT(*)"]
    assert_equal 2, urls_before

    # Delete the deleted_file record
    db.execute("DELETE FROM deleted_files WHERE id = ?", [file_id])

    # Verify associated URLs were also deleted (CASCADE)
    urls_after_result = db.execute("SELECT COUNT(*) FROM download_urls WHERE deleted_file_id = ?", [file_id])
    urls_after = urls_after_result.first["COUNT(*)"]
    assert_equal 0, urls_after, "Associated URLs should be deleted when deleted_file is removed"
  end
end