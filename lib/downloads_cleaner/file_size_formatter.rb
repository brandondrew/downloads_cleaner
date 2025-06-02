# frozen_string_literal: true

module DownloadsCleaner
  # Utility module for file size formatting
  module FileSizeFormatter
    def self.parse_size(size_string)
      case size_string.downcase
      when /^(\d+(?:\.\d+)?)gb?$/
        (::Regexp.last_match(1).to_f * 1024 * 1024 * 1024).to_i
      when /^(\d+(?:\.\d+)?)mb?$/
        (::Regexp.last_match(1).to_f * 1024 * 1024).to_i
      when /^(\d+(?:\.\d+)?)kb?$/
        (::Regexp.last_match(1).to_f * 1024).to_i
      when /^(\d+)$/
        ::Regexp.last_match(1).to_i
      else
        raise ArgumentError, "Invalid size format. Use formats like: 100MB, 1.5GB, 500KB, or raw bytes"
      end
    end

    def self.format_size(bytes)
      if bytes >= 1024 * 1024 * 1024
        "#{(bytes.to_f / (1024 * 1024 * 1024)).round(1)}GB"
      elsif bytes >= 1024 * 1024
        "#{(bytes.to_f / (1024 * 1024)).round(1)}MB"
      elsif bytes >= 1024
        "#{(bytes.to_f / 1024).round(1)}KB"
      else
        "#{bytes} bytes"
      end
    end
  end
end
