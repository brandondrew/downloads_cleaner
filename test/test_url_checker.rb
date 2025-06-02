require 'minitest/autorun'
require 'webmock/minitest'
require_relative "../lib/downloads_cleaner"

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

    assert UrlChecker.accessible?("https://example.com")
  end

  def test_redirect_url_returns_true
    # Mock a redirect HTTP response (3xx is considered accessible)
    stub_request(:head, "https://example.com/redirect")
      .to_return(status: 302, body: "", headers: { 'Location' => 'https://example.com/new-location' })

    assert UrlChecker.accessible?("https://example.com/redirect")
  end

  def test_error_url_returns_false
    # Mock a 404 response
    stub_request(:head, "https://example.com/not-found")
      .to_return(status: 404, body: "", headers: {})

    refute UrlChecker.accessible?("https://example.com/not-found")
  end

  def test_server_error_url_returns_false
    # Mock a 500 response
    stub_request(:head, "https://example.com/server-error")
      .to_return(status: 500, body: "", headers: {})

    refute UrlChecker.accessible?("https://example.com/server-error")
  end

  def test_timeout_returns_false
    # Mock a timeout
    stub_request(:head, "https://example.com/timeout")
      .to_timeout

    refute UrlChecker.accessible?("https://example.com/timeout")
  end

  def test_connection_refused_returns_false
    # Mock a connection refused error
    stub_request(:head, "https://example.com/connection-refused")
      .to_raise(Errno::ECONNREFUSED)

    refute UrlChecker.accessible?("https://example.com/connection-refused")
  end

  def test_invalid_url_returns_false
    refute UrlChecker.accessible?("not-a-valid-url")
  end

  def test_empty_url_returns_false
    refute UrlChecker.accessible?("")
  end

  def test_nil_url_returns_false
    refute UrlChecker.accessible?(nil)
  end
end
