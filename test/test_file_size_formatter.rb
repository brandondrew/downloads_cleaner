require 'minitest/autorun'
require_relative "../lib/downloads_cleaner"

class TestFileSizeFormatter < Minitest::Test
  def test_parse_size_with_gb
    assert_equal 1073741824, FileSizeFormatter.parse_size("1GB")
    assert_equal 1073741824, FileSizeFormatter.parse_size("1gb")
    assert_equal 1073741824, FileSizeFormatter.parse_size("1G")
    assert_equal 1610612736, FileSizeFormatter.parse_size("1.5GB")
  end

  def test_parse_size_with_mb
    assert_equal 104857600, FileSizeFormatter.parse_size("100MB")
    assert_equal 104857600, FileSizeFormatter.parse_size("100mb")
    assert_equal 104857600, FileSizeFormatter.parse_size("100M")
    assert_equal 15728640, FileSizeFormatter.parse_size("15.0MB")
  end

  def test_parse_size_with_kb
    assert_equal 1024, FileSizeFormatter.parse_size("1KB")
    assert_equal 1024, FileSizeFormatter.parse_size("1kb")
    assert_equal 1024, FileSizeFormatter.parse_size("1K")
    assert_equal 1536, FileSizeFormatter.parse_size("1.5KB")
  end

  def test_parse_size_with_bytes
    assert_equal 1024, FileSizeFormatter.parse_size("1024")
    assert_equal 0, FileSizeFormatter.parse_size("0")
  end

  def test_parse_size_with_invalid_format
    assert_raises(ArgumentError) do
      FileSizeFormatter.parse_size("invalid")
    end

    assert_raises(ArgumentError) do
      FileSizeFormatter.parse_size("100XB")
    end
  end

  def test_format_size_in_gb_range
    assert_equal "1.0GB", FileSizeFormatter.format_size(1073741824)
    assert_equal "1.5GB", FileSizeFormatter.format_size(1610612736)
  end

  def test_format_size_in_mb_range
    assert_equal "100.0MB", FileSizeFormatter.format_size(104857600)
    assert_equal "10.5MB", FileSizeFormatter.format_size(11010048)
  end

  def test_format_size_in_kb_range
    assert_equal "1.0KB", FileSizeFormatter.format_size(1024)
    assert_equal "1.5KB", FileSizeFormatter.format_size(1536)
  end

  def test_format_size_in_bytes_range
    assert_equal "100 bytes", FileSizeFormatter.format_size(100)
    assert_equal "0 bytes", FileSizeFormatter.format_size(0)
  end
end
