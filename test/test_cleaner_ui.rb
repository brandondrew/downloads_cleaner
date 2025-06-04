require_relative 'test_helper'
require 'stringio'

# Test double for url_checker with configurable compare_with_local
class DummyUrlChecker
  def initialize(comparison_result)
    @comparison_result = comparison_result
  end

  def check_url(url)
    # Always accessible for integration tests
    { accessible: true, url_type: 'file', etag: nil, last_modified: @comparison_result[:last_modified] }
  end

  def compare_with_local(url, local_md5)
    @comparison_result
  end
end

class DummyFileSystem
  def self.file_exists?(path); true; end
  def self.file_size(path); 1234; end
  def self.file_mtime(path); @dummy_mtime || Time.now; end
  def self.set_dummy_mtime(t); @dummy_mtime = t; end
  def self.basename(path, ext = nil); 'dummy.txt'; end
end

class TestCleanerUI < Minitest::Test
  def setup
    @file_info = {
      path: '/tmp/dummy.txt',
      name: 'dummy.txt',
      size: 1234,
      download_urls: [
        { url: 'https://example.com/dummy.txt', accessible: true, url_type: 'file', last_modified: nil }
      ]
    }
    # Stub Digest::MD5.file to always return an object with hexdigest
    @digest_stub = Minitest::Mock.new
    def @digest_stub.hexdigest; 'd41d8cd98f00b204e9800998ecf8427e'; end
    Digest::MD5.stub :file, @digest_stub do
      yield if block_given?
    end
  end

  def run_cleaner_with(comparison_result, local_mtime: nil)
    url_checker = DummyUrlChecker.new(comparison_result)
    DummyFileSystem.set_dummy_mtime(local_mtime) if local_mtime
    file_info = @file_info.dup
    # For last-modified tests, set the value in the download_urls hash
    if comparison_result[:comparison_method] == :last_modified && comparison_result[:last_modified]
      file_info = Marshal.load(Marshal.dump(@file_info)) # deep dup
      file_info[:download_urls][0][:last_modified] = comparison_result[:last_modified]
    end
    Digest::MD5.stub :file, @digest_stub do
      cleaner = DownloadsCleaner::Cleaner.new(filesystem: DummyFileSystem, url_checker: url_checker)
      cleaner.instance_variable_set(:@retrievable_files, [file_info])
      out = capture_stdout { cleaner.send(:display_retrievable_files) }
      out
    end
  end

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  def test_ui_shows_lock_emoji_for_md5_match
    out = run_cleaner_with({ changed: false, comparison_method: :etag_md5 })
    assert_includes out, '🔒', 'Should show lock emoji for MD5/etag match'
  end

  def test_ui_shows_arrows_emoji_for_md5_mismatch
    out = run_cleaner_with({ changed: true, comparison_method: :etag_md5 })
    assert_includes out, '🔄', 'Should show arrows emoji for MD5/etag mismatch'
  end

  def test_ui_shows_clock_emoji_for_last_modified_match
    local_time = Time.httpdate('Wed, 21 Oct 2015 07:28:00 GMT')
    out = run_cleaner_with({ changed: true, comparison_method: :last_modified, last_modified: 'Wed, 21 Oct 2015 07:28:00 GMT' }, local_mtime: local_time)
    assert_includes out, '🕒', 'Should show clock emoji for last-modified match'
    assert_includes out, 'heuristic', 'Should clarify heuristic nature'
  end

  def test_ui_shows_arrows_emoji_for_last_modified_mismatch
    remote_time = 'Wed, 21 Oct 2015 07:28:00 GMT'
    local_time = Time.httpdate('Wed, 21 Oct 2015 08:00:00 GMT')
    out = run_cleaner_with({ changed: true, comparison_method: :last_modified, last_modified: remote_time }, local_mtime: local_time)
    assert_includes out, '🔄', 'Should show arrows emoji for last-modified mismatch'
  end

  def test_ui_shows_yellow_for_no_remote_info
    out = run_cleaner_with({ changed: true, comparison_method: :none })
    assert_includes out, '🟡', 'Should show yellow emoji for no remote info'
  end
end
