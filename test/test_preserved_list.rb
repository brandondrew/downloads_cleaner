require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/downloads_cleaner/preserved_list'

class TestPreservedList < Minitest::Test
  TMP_PATH = File.expand_path("../tmp/test_preserved_list.txt", __dir__)

  def setup
    FileUtils.rm_f(TMP_PATH)
    @plist = DownloadsCleaner::PreservedList.new(TMP_PATH)
  end

  def teardown
    FileUtils.rm_f(TMP_PATH)
  end

  def test_initial_empty
    assert_equal [], @plist.files
    refute @plist.include?('/tmp/somefile')
  end

  def test_add_and_include
    @plist.add('/tmp/somefile')
    assert @plist.include?('/tmp/somefile')
    assert_equal [File.expand_path('/tmp/somefile')], @plist.files
  end

  def test_persistence
    @plist.add('/tmp/somefile')
    @plist2 = DownloadsCleaner::PreservedList.new(TMP_PATH)
    assert @plist2.include?('/tmp/somefile')
  end

  def test_no_duplicates
    2.times { @plist.add('/tmp/somefile') }
    assert_equal 1, @plist.files.size
  end

  def test_multiple_files
    @plist.add('/tmp/a')
    @plist.add('/tmp/b')
    assert @plist.include?('/tmp/a')
    assert @plist.include?('/tmp/b')
    assert_equal [File.expand_path('/tmp/a'), File.expand_path('/tmp/b')], @plist.files.sort
  end
end
