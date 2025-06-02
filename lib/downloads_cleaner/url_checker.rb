# frozen_string_literal: true

module DownloadsCleaner
  # URL accessibility checker
  class UrlChecker
    def self.accessible?(url)
      uri = URI.parse(url)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.open_timeout = 10
        http.read_timeout = 10

        response = http.head(uri.path.empty? ? "/" : uri.path)

        # Consider 2xx and 3xx as accessible
        response.code.to_i < 400
      end
    rescue StandardError
      false
    end
  end
end
