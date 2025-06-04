require_relative 'test_helper'

class TestUrlChecker < Minitest::Test
  def setup
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def teardown
    WebMock.allow_net_connect!
  end

  def test_accessible_url_returns_true
    # Mock a successful HTTP response
    stub_request(:head, "https://example.com/")
      .to_return(status: 200, body: "", headers: {})

    assert DownloadsCleaner::UrlChecker.accessible?("https://example.com")
  end

  def test_redirect_url_returns_true
    # Mock a redirect HTTP response (3xx is considered accessible)
    stub_request(:head, "https://example.com/redirect")
      .to_return(status: 302, body: "", headers: { 'Location' => 'https://example.com/new-location' })

    assert DownloadsCleaner::UrlChecker.accessible?("https://example.com/redirect")
  end

  def test_error_url_returns_false
    # Mock a 404 response
    stub_request(:head, "https://example.com/not-found")
      .to_return(status: 404, body: "", headers: {})

    refute DownloadsCleaner::UrlChecker.accessible?("https://example.com/not-found")
  end

  def test_server_error_url_returns_false
    # Mock a 500 response
    stub_request(:head, "https://example.com/server-error")
      .to_return(status: 500, body: "", headers: {})

    refute DownloadsCleaner::UrlChecker.accessible?("https://example.com/server-error")
  end

  def test_timeout_returns_false
    # Mock a timeout
    stub_request(:head, "https://example.com/timeout")
      .to_timeout

    refute DownloadsCleaner::UrlChecker.accessible?("https://example.com/timeout")
  end

  def test_connection_refused_returns_false
    # Mock a connection refused error
    stub_request(:head, "https://example.com/connection-refused")
      .to_raise(Errno::ECONNREFUSED)

    refute DownloadsCleaner::UrlChecker.accessible?("https://example.com/connection-refused")
  end

  def test_invalid_url_returns_false
    refute DownloadsCleaner::UrlChecker.accessible?("not-a-valid-url")
  end

  def test_empty_url_returns_false
    refute DownloadsCleaner::UrlChecker.accessible?("")
  end

  def test_nil_url_returns_false
    refute DownloadsCleaner::UrlChecker.accessible?(nil)
  end

  # =====================
  # compare_with_local tests
  # =====================
  def test_compare_with_local_etag_md5_match
    stub_request(:head, "https://example.com/file.zip")
      .to_return(status: 200, headers: { 'ETag' => '"d41d8cd98f00b204e9800998ecf8427e"' })
    local_md5 = 'd41d8cd98f00b204e9800998ecf8427e'
    result = DownloadsCleaner::UrlChecker.compare_with_local("https://example.com/file.zip", local_md5)
    refute result[:changed], "Should detect no change when ETag matches local MD5"
    assert_equal :etag_md5, result[:comparison_method]
  end

  def test_compare_with_local_etag_md5_no_match
    stub_request(:head, "https://example.com/file.zip")
      .to_return(status: 200, headers: { 'ETag' => '"d41d8cd98f00b204e9800998ecf8427e"' })
    local_md5 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    result = DownloadsCleaner::UrlChecker.compare_with_local("https://example.com/file.zip", local_md5)
    assert result[:changed], "Should detect change when ETag does not match local MD5"
    assert_equal :etag_md5, result[:comparison_method]
  end

  def test_compare_with_local_etag_non_md5
    stub_request(:head, "https://example.com/file.zip")
      .to_return(status: 200, headers: { 'ETag' => '"not-an-md5-hash"' })
    local_md5 = 'd41d8cd98f00b204e9800998ecf8427e'
    result = DownloadsCleaner::UrlChecker.compare_with_local("https://example.com/file.zip", local_md5)
    assert result[:changed], "Should conservatively assume changed for non-MD5 ETag"
    assert_equal :etag_unknown, result[:comparison_method]
  end

  def test_compare_with_local_last_modified_only
    stub_request(:head, "https://example.com/file.txt")
      .to_return(status: 200, headers: { 'Last-Modified' => 'Wed, 21 Oct 2015 07:28:00 GMT' })
    local_md5 = 'd41d8cd98f00b204e9800998ecf8427e'
    result = DownloadsCleaner::UrlChecker.compare_with_local("https://example.com/file.txt", local_md5)
    assert result[:changed], "Should conservatively assume changed with only Last-Modified"
    assert_equal :last_modified, result[:comparison_method]
  end

  def test_compare_with_local_no_etag_no_last_modified
    stub_request(:head, "https://example.com/file.txt")
      .to_return(status: 200, headers: {})
    local_md5 = 'd41d8cd98f00b204e9800998ecf8427e'
    result = DownloadsCleaner::UrlChecker.compare_with_local("https://example.com/file.txt", local_md5)
    assert result[:changed], "Should conservatively assume changed with no ETag or Last-Modified"
    assert_equal :none, result[:comparison_method]
  end

  def test_compare_with_local_url_inaccessible
    stub_request(:head, "https://example.com/file.txt")
      .to_return(status: 404, headers: {})
    local_md5 = 'd41d8cd98f00b204e9800998ecf8427e'
    result = DownloadsCleaner::UrlChecker.compare_with_local("https://example.com/file.txt", local_md5)
    assert result[:changed], "Should conservatively assume changed if URL is inaccessible"
    assert_equal :error, result[:comparison_method]
  end
end
