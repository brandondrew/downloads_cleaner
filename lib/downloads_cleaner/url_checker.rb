# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'digest'

module DownloadsCleaner
  # Checks URL accessibility and determines its type based on HTTP headers
  class UrlChecker
    # Checks a URL and returns its accessibility, content type, content disposition, and determined URL type.
    #
    # @param url_string [String] The URL to check.
    # @return [Hash] A hash containing:
    #   - :accessible [Boolean] True if the URL is accessible (2xx or 3xx response), false otherwise.
    #   - :content_type [String, nil] The Content-Type header, or nil if not found/error.
    #   - :content_disposition [String, nil] The Content-Disposition header, or nil if not found/error.
    #   - :url_type [String] "file" or "site", determined from headers. Defaults to "site" on error or ambiguity.
    #   - :status_code [Integer, nil] The HTTP status code, or nil on error.
    #   - :error [String, nil] Error message if an exception occurred.
    def self.check_url(url_string)
      uri = URI.parse(url_string)
      result = {
        accessible: false,
        content_type: nil,
        content_disposition: nil,
        url_type: "site", # Default to site
        status_code: nil,
        error: nil,
        etag: nil,
        last_modified: nil
      }

      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 5 # seconds
        http.read_timeout = 5 # seconds

        request = Net::HTTP::Head.new(uri.request_uri)
        request['User-Agent'] = "DownloadsCleaner/#{DownloadsCleaner::VERSION} (Ruby/#{RUBY_VERSION})"

        response = http.request(request)

        result[:status_code] = response.code.to_i
        result[:content_type] = response['content-type']&.downcase
        result[:content_disposition] = response['content-disposition']&.downcase
        result[:etag] = response['etag']
        result[:last_modified] = response['last-modified']

        if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
          result[:accessible] = true
          # Determine URL type
          if result[:content_disposition]&.include?('attachment')
            result[:url_type] = "file"
          elsif result[:content_type]
            if result[:content_type].start_with?('application/', 'image/', 'audio/', 'video/') &&
               !result[:content_type].include?('html') &&
               !result[:content_type].include?('xml') && # application/xml is often a site
               !result[:content_type].include?('json') && # application/json could be an API, not a direct file
               !result[:content_type].include?('xhtml')
              result[:url_type] = "file"
            elsif result[:content_type].include?('text/plain') && result[:content_disposition] # text/plain with disposition is a file
              result[:url_type] = "file"
            else
              result[:url_type] = "site" # Default for other text/*, application/json, etc.
            end
          else
            # No content-type, but accessible. Could be a redirect to a file.
            # For HEAD requests, it's hard to tell without following. Default to site.
            result[:url_type] = "site"
          end
        else
          result[:accessible] = false
          result[:url_type] = "site" # Inaccessible, assume site
        end

      rescue SocketError => e
        result[:error] = "SocketError: #{e.message}"
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        result[:error] = "Timeout: #{e.message}"
      rescue StandardError => e
        result[:error] = "Error: #{e.class} - #{e.message}"
      end # End of begin/rescue block

      result # This is now the last line INSIDE the method
    end # End of self.check_url method
    
    # Convenience method that returns true if the URL is accessible, false otherwise
    # @param url_string [String] The URL to check
    # @return [Boolean] True if the URL is accessible, false otherwise
    def self.accessible?(url_string)
      return false if url_string.nil? || url_string.empty?
      
      begin
        result = check_url(url_string)
        result[:accessible]
      rescue StandardError => _error
        false
      end
    end
    
    # Compare remote file with local file using HTTP headers
    # @param url_string [String] The URL to check
    # @param local_md5 [String] MD5 hash of the local file
    # @return [Hash] Comparison result with :changed, :comparison_method, and :details keys
    def self.compare_with_local(url_string, local_md5)
      return { changed: true, comparison_method: :error, details: 'Invalid URL' } if url_string.nil? || url_string.empty?
      
      begin
        result = check_url(url_string)
        
        # If URL isn't accessible, we can't compare
        unless result[:accessible]
          return { 
            changed: true, 
            comparison_method: :error, 
            details: result[:error] || 'URL not accessible' 
          }
        end
        
        # Use ETag if available
        if result[:etag]
          # ETags are often surrounded by quotes, so we need to strip them
          clean_etag = result[:etag].gsub(/^\"|\"|^'|'$/, '')
          
          # Some ETags are actually MD5 hashes or include them
          if clean_etag.length == 32 && clean_etag =~ /^[a-f0-9]{32}$/i
            return { 
              changed: clean_etag.downcase != local_md5.downcase, 
              comparison_method: :etag_md5,
              details: {
                etag: clean_etag,
                local_md5: local_md5
              }
            }
          else
            # For other types of ETags, we can only tell if they've changed
            # from a previous value, not compare with local MD5
            return { 
              changed: true, # Conservative approach: assume changed
              comparison_method: :etag_unknown,
              details: {
                etag: clean_etag,
                note: 'ETag format not recognized as MD5'
              }
            }
          end
        end
        
        # If no ETag, try Last-Modified
        if result[:last_modified]
          return { 
            changed: true, # Conservative approach: assume changed
            comparison_method: :last_modified,
            details: {
              last_modified: result[:last_modified],
              note: 'Cannot precisely compare with local MD5'
            }
          }
        end
        
        # No reliable comparison method available
        return { 
          changed: true, # Conservative approach
          comparison_method: :none,
          details: 'No comparison method available (no ETag or Last-Modified header)'
        }
      rescue StandardError => error
        return { 
          changed: true, 
          comparison_method: :error, 
          details: "Error: #{error.message}" 
        }
      end
    end
  end # End of class UrlChecker
end
