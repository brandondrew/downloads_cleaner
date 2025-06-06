# frozen_string_literal: true

module DownloadsCleaner
  # Utility to write macOS .webloc files for URLs
  class WeblocWriter
    # Write a .webloc file next to the deleted file, with the original URL
    # @param original_path [String] the path of the deleted file
    # @param url [String] the URL to embed in the .webloc file
    # @return [String] path to the created .webloc file
    def self.write_webloc(original_path, url)
      webloc_path = "#{original_path}.webloc"
      content = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
          <dict>
            <key>URL</key>
            <string>#{url}</string>
          </dict>
        </plist>
      XML
      File.write(webloc_path, content)
      webloc_path
    rescue => e
      warn "[DownloadsCleaner::WeblocWriter] Failed to write .webloc for #{original_path}: #{e.message}"
      nil
    end
  end
end
