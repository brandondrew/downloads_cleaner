require_relative 'test_helper'

class TestFileSystem < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @test_file_path = File.join(@temp_dir, "test_file.txt")
    File.write(@test_file_path, "test content")
  end

  def teardown
    FileUtils.remove_entry @temp_dir
  end

  def test_downloads_path
    # This test is system-dependent, but we can at least verify it returns a string
    path = DownloadsCleaner::FileSystem.downloads_path
    assert_kind_of String, path
    assert path.include?("Downloads")
  end

  def test_file_exists
    assert DownloadsCleaner::FileSystem.file_exists?(@test_file_path)
    assert !DownloadsCleaner::FileSystem.file_exists?(File.join(@temp_dir, "nonexistent.txt"))
  end

  def test_directory_exists
    assert DownloadsCleaner::FileSystem.directory_exists?(@temp_dir)
    assert !DownloadsCleaner::FileSystem.directory_exists?(File.join(@temp_dir, "nonexistent_dir"))
  end

  def test_file_size
    assert_equal 12, DownloadsCleaner::FileSystem.file_size(@test_file_path) # "test content" is 12 bytes
  end

  def test_delete_file
    temp_file = Tempfile.new(["test", ".txt"], @temp_dir)
    path = temp_file.path
    temp_file.close

    assert DownloadsCleaner::FileSystem.file_exists?(path)
    DownloadsCleaner::FileSystem.delete_file(path)
    assert !DownloadsCleaner::FileSystem.file_exists?(path)
  end

  def test_get_files_in_directory
    # Create a few test files
    file1 = File.join(@temp_dir, "file1.txt")
    file2 = File.join(@temp_dir, "file2.txt")
    File.write(file1, "content1")
    File.write(file2, "content2")

    # Create a subdirectory (should not be returned)
    subdir = File.join(@temp_dir, "subdir")
    Dir.mkdir(subdir)

    files = DownloadsCleaner::FileSystem.get_files_in_directory(@temp_dir)
    assert_includes files, file1
    assert_includes files, file2
    assert_includes files, @test_file_path
    assert_equal 3, files.length # Only files, not directories
  end

  def test_basename
    assert_equal "test_file.txt", DownloadsCleaner::FileSystem.basename(@test_file_path)
    assert_equal "test_file", DownloadsCleaner::FileSystem.basename(@test_file_path, ".txt")
  end

  def test_write_and_read_file
    test_content = "This is test content for write/read test"
    test_file = File.join(@temp_dir, "write_read_test.txt")

    DownloadsCleaner::FileSystem.write_file(test_file, test_content)
    assert DownloadsCleaner::FileSystem.file_exists?(test_file)

    content = DownloadsCleaner::FileSystem.read_file(test_file)
    assert_equal test_content, content
  end
end
