# frozen_string_literal: true

require_relative "database"
require_relative "preserved_list"
require "digest"

module DownloadsCleaner
  # Main class that handles finding and cleaning up large downloadable files
  class Cleaner
    attr_reader :large_files, :retrievable_files, :options

    def initialize(options = {})
      @options = {
        threshold: 100 * 1024 * 1024, # 100MB default
        mode: :prompt,
        filesystem: FileSystem,
        url_checker: UrlChecker
      }.merge(options)

      @large_files = []
      @retrievable_files = []
      @filesystem = @options.delete(:filesystem)
      @url_checker = @options.delete(:url_checker)
      @database = Database.new
      preserved_list_path = @options.delete(:preserved_list_path)
      @preserved_list = PreservedList.new(preserved_list_path)
    end

    def run(args = ARGV)
      result = parse_arguments(args)
      return if result == :exit
      find_large_files
      check_retrievability
      display_result = display_retrievable_files
      return if display_result == :exit
      handle_deletion
    end

    private

    def parse_arguments(args = [])
      option_parser = OptionParser.new do |opts|
        opts.banner = "Usage: downloads_cleaner [options] SIZE_THRESHOLD"

        opts.on("--delete", "Delete files immediately without prompting") do
          @options[:mode] = :delete
        end

        opts.on("--prompt", "Prompt before deleting (default)") do
          @options[:mode] = :prompt
        end

        opts.on("-h", "--help", "Show this help message") do
          puts opts
          STDOUT.flush
          return :exit # Return instead of exit for testability
        end

        opts.on("-v", "--version", "Show version") do
          puts "downloads_cleaner version #{DownloadsCleaner::VERSION}"
          STDOUT.flush
          return :exit
        end
      end

      remaining_args = option_parser.parse(args)

      if remaining_args.length > 0
        size_arg = remaining_args[0]
        begin
          @options[:threshold] = FileSizeFormatter.parse_size(size_arg)
        rescue ArgumentError => e
          puts e.message
          return :exit
        end
      end

      puts "Looking for files larger than #{FileSizeFormatter.format_size(@options[:threshold])}"
      :continue
    end

    def find_large_files
      downloads_path = @filesystem.downloads_path

      unless @filesystem.directory_exists?(downloads_path)
        puts "Downloads folder not found at #{downloads_path}"
        return :exit
      end

      puts "Scanning #{downloads_path} for large files..."

      preserved_files = @preserved_list.files

      @filesystem.get_files_in_directory(downloads_path).each do |file_path|
        file_size = @filesystem.file_size(file_path)
        next unless file_size > @options[:threshold]
        next if preserved_files.include?(File.expand_path(file_path))

        @large_files << {
          path: file_path,
          name: @filesystem.basename(file_path),
          size: file_size,
        }
      end

      puts "Found #{@large_files.length} files above threshold (excluding preserved files)"
      :continue
    end

    def check_retrievability
      return :continue if @large_files.empty?

      puts "Checking if files can be retrieved online..."

      @large_files.each_with_index do |file_info, index|
        print "Checking #{file_info[:name]} (#{index + 1}/#{@large_files.length})... "

        urls = get_download_urls(file_info[:path])

        if urls && !urls.empty?
          file_info[:download_urls] = urls
          @retrievable_files << file_info
          puts "✅ retrievable (#{urls.length} URL#{'s' if urls.length > 1} found)"
        else
          puts "❌ URL not available"
        end
      end

      :continue
    end

    def get_download_urls(file_path)
      urls = []

      # Try to get URLs from macOS extended attributes (where metadata)
      urls_from_metadata = get_urls_from_metadata(file_path)
      urls.concat(urls_from_metadata) if urls_from_metadata.any?

      # Try alternative metadata sources if no URLs found
      if urls.empty?
        alt_url = get_url_from_alternative_sources(file_path)
        if alt_url
          urls << alt_url
        end
      end

      urls
    end

    def get_urls_from_metadata(file_path)
      urls = []

      begin
        # Get the hex data from xattr and convert to binary for plutil
        hex_data = `xattr -px com.apple.metadata:kMDItemWhereFroms "#{file_path}" 2>/dev/null`.strip

        if $?.success? && !hex_data.empty?
          # Convert hex to binary and then to XML plist
          temp_file = Tempfile.new(['xattr', '.plist'])
          begin
            # Convert hex to binary using xxd
            system("echo '#{hex_data}' | xxd -r -p > \"#{temp_file.path}\"")

            if $?.success? && @filesystem.file_size(temp_file.path) > 0
              # Convert binary plist to XML format
              xml_output = `plutil -convert xml1 -o - "#{temp_file.path}" 2>/dev/null`

              if $?.success? && !xml_output.strip.empty?
                found_urls = extract_urls_from_plist_xml(xml_output)

                # Add all found URLs with accessibility status
                found_urls.each do |url|
                  check_result = @url_checker.check_url(url)
                  urls << { 
                    url: url, 
                    accessible: check_result[:accessible], 
                    url_type: check_result[:url_type],
                    etag: check_result[:etag],
                    last_modified: check_result[:last_modified]
                  }
                end
              end
            end
          ensure
            temp_file.close
            temp_file.unlink
          end
        end
      rescue StandardError
        # Fallback methods could go here
      end

      urls
    end

    def extract_urls_from_plist_xml(xml_data)
      urls = []

      # Extract URLs from the XML plist format
      # The URLs are typically in <string> tags
      xml_data.scan(/<string>(https?:\/\/[^<]+)<\/string>/) do |url|
        urls << url.first
      end

      urls.uniq
    end

    def get_url_from_alternative_sources(file_path)
      # Try to find .url files or other metadata
      base_name = @filesystem.basename(file_path, File.extname(file_path))
      dir_name = File.dirname(file_path)

      # Look for companion .url file
      url_file = File.join(dir_name, "#{base_name}.url")
      if @filesystem.file_exists?(url_file)
        content = @filesystem.read_file(url_file)
        url_match = content.match(/URL=(.+)/)
        if url_match
          url = url_match[1].strip
          check_result = @url_checker.check_url(url)
          return { 
            url: url, 
            accessible: check_result[:accessible], 
            url_type: check_result[:url_type],
            etag: check_result[:etag],
            last_modified: check_result[:last_modified]
          }
        end
      end

      nil
    end

    def display_retrievable_files
      if @retrievable_files.empty?
        puts "\nNo large files found that can be retrieved online."
        puts "Have a great day! 👋"
        return :exit
      end

      puts "\n" + "=" * 80
      puts "FILES THAT CAN BE DELETED AND RETRIEVED LATER:"
      puts "=" * 80

      total_size = 0
      @retrievable_files.each_with_index do |file_info, index|
        total_size += file_info[:size]
        puts "#{index + 1}. #{file_info[:name]}"
        puts "   Size: #{FileSizeFormatter.format_size(file_info[:size])}"
        
        # Check if we have a local MD5 hash for this file
        local_md5 = nil
        begin
          if @filesystem.file_exists?(file_info[:path])
            local_md5 = Digest::MD5.file(file_info[:path]).hexdigest
            file_info[:md5] = local_md5
          end
        rescue StandardError => e
          puts "Warning: Could not compute MD5 for #{file_info[:name]}: #{e.message}"
        end

        # Display all URLs with their accessibility status and type
        if file_info[:download_urls].length == 1
          url_info = file_info[:download_urls].first
          status = url_info[:accessible] ? "✅" : "⚠️"
          type_indicator = url_info[:url_type] == "file" ? "📁" : "🌐"
          
          # Compare remote and local versions if we have MD5
          version_status = ""
          if local_md5 && url_info[:accessible]
            comparison = if @url_checker.respond_to?(:compare_with_local)
              @url_checker.compare_with_local(url_info[:url], local_md5)
            else
              { changed: true, comparison_method: :none, details: 'compare_with_local not implemented' }
            end
            case comparison[:comparison_method]
            when :etag_md5
              version_status = comparison[:changed] ? " 🔄 Remote file differs from local" : " 🔒 Remote file matches local"
            when :etag_unknown
              version_status = " 🟡 ETag present but not MD5 (cannot verify exact match)"
            when :last_modified
              # Try to compare last-modified to local mtime
              if url_info[:last_modified]
                begin
                  remote_time = Time.httpdate(url_info[:last_modified]) rescue nil
                  local_time = @filesystem.file_mtime(file_info[:path]) rescue nil
                  if remote_time && local_time && remote_time.to_i == local_time.to_i
                    version_status = " 🕒 Likely matches local (last-modified)"
                  else
                    version_status = " 🔄 Remote file likely changed (last-modified mismatch)"
                  end
                rescue => e
                  version_status = " 🟡 Could not compare last-modified: #{e.message}"
                end
              else
                version_status = " 🟡 Last-Modified header present but not parsed"
              end
            when :none
              version_status = " 🟡 No remote version info available"
            else
              version_status = comparison[:changed] ? " 🔄 Remote file differs from local" : " 🔒 Remote file matches local"
            end
          end
          
          puts "   URL: #{url_info[:url]} #{status} #{type_indicator}#{version_status}"
          puts "     (🕒 means last-modified matches your local file's mtime; this is a heuristic, not a guarantee)" if version_status.include?("🕒")
        else
          puts "   URLs:"
          file_info[:download_urls].each_with_index do |url_info, url_index|
            status = url_info[:accessible] ? "✅" : "⚠️"
            type_indicator = url_info[:url_type] == "file" ? "📁" : "🌐"
            
            # Compare remote and local versions if we have MD5
            version_status = ""
            if local_md5 && url_info[:accessible]
              comparison = @url_checker.compare_with_local(url_info[:url], local_md5)
              if comparison[:changed]
                version_status = " 🔄 Remote file differs from local"
              else
                version_status = " 🔒 Remote file matches local"
              end
            end
            
            puts "     #{url_index + 1}. #{url_info[:url]} #{status} #{type_indicator}#{version_status}"
          end
        end
        puts
      end

      puts "Total size that can be freed: #{FileSizeFormatter.format_size(total_size)}"
      puts "=" * 80

      :continue
    end

    def handle_deletion
      result = case @options[:mode]
               when :delete
                 delete_all_files
               when :prompt
                 prompt_for_deletion
               end

      result
    end

    def prompt_for_deletion
      total = @retrievable_files.size
      puts "\nWhat would you like to do?"
      if total == 1
        file_name = @retrievable_files.first[:name]
        puts "0. Delete zero files and exit"
        puts "1. Delete #{file_name}"
        print "\nEnter your choice (0-1): "
        input = $stdin.gets
        choice = input ? input.chomp.strip : "0"
        case choice
        when "1"
          delete_all_files
        else
          puts "\nNo files deleted. Have a great day! 👋"
          return :exit
        end
      else
        puts "0. Delete zero files and exit"
        puts "1. Choose files one-by-one"
        puts "#{total}. Delete all files listed above"
        print "\nEnter your choice (0, 1, or #{total}): "
        input = $stdin.gets
        choice = input ? input.chomp.strip : "0"
        case choice
        when "1"
          delete_files_individually
        when total.to_s
          delete_all_files
        else
          puts "\nNo files deleted. Have a great day! 👋"
          return :exit
        end
      end
    end

    def delete_all_files
      deleted_files = @retrievable_files.dup

      # Compute MD5 hashes before deleting files
      puts "\nComputing file hashes..."
      deleted_files.each do |file_info|
        begin
          if @filesystem.file_exists?(file_info[:path])
            file_info[:md5] = Digest::MD5.file(file_info[:path]).hexdigest
          else
            file_info[:md5] = ""
          end
        rescue => e
          puts "Warning: Could not compute MD5 for #{file_info[:name]}: #{e.message}"
          file_info[:md5] = ""
        end
      end

      puts "\nDeleting all retrievable files..."
      @retrievable_files.each do |file_info|
        @filesystem.delete_file(file_info[:path])
        puts "🗑 Deleted #{file_info[:name]}"
      end

      save_deleted_files_list(deleted_files)
      puts "\nAll files deleted successfully! 🎉"
      puts "URLs saved to retrievable downloads list."

      :exit
    end

    def delete_files_individually
      deleted_files = []

      @retrievable_files.each do |file_info|
        puts "\n" + "-" * 60
        puts "File: #{file_info[:name]}"
        puts "Size: #{FileSizeFormatter.format_size(file_info[:size])}"
        
        # If MD5 hasn't been computed yet, do it now
        local_md5 = nil
        if !file_info[:md5]
          begin
            if @filesystem.file_exists?(file_info[:path])
              local_md5 = Digest::MD5.file(file_info[:path]).hexdigest
              file_info[:md5] = local_md5
            end
          rescue StandardError => e
            puts "Warning: Could not compute MD5 for #{file_info[:name]}: #{e.message}"
          end
        else
          local_md5 = file_info[:md5]
        end
        
        if file_info[:download_urls].length == 1
          url_info = file_info[:download_urls].first
          status = url_info[:accessible] ? "✅" : "⚠️"
          
          # Compare remote and local versions if we have MD5
          version_status = ""
          if local_md5 && url_info[:accessible]
            comparison = if @url_checker.respond_to?(:compare_with_local)
              @url_checker.compare_with_local(url_info[:url], local_md5)
            else
              { changed: true, comparison_method: :none, details: 'compare_with_local not implemented' }
            end
            if comparison[:changed]
              version_status = " 🔄 Remote file differs from local"
            else
              version_status = " 🔒 Remote file matches local"
            end
          end
          
          puts "URL:  #{url_info[:url]} #{status}#{version_status}"
        else
          puts "URLs:"
          file_info[:download_urls].each_with_index do |url_info, idx|
            status = url_info[:accessible] ? "✅" : "⚠️"
            
            # Compare remote and local versions if we have MD5
            version_status = ""
            if local_md5 && url_info[:accessible]
              comparison = @url_checker.compare_with_local(url_info[:url], local_md5)
              if comparison[:changed]
                version_status = " 🔄 Remote file differs from local"
              else
                version_status = " 🔒 Remote file matches local"
              end
            end
            
            puts "      #{idx + 1}. #{url_info[:url]} #{status}#{version_status}"
          end
        end

        puts "Options:"
        puts "  D. Delete this file"
        puts "  K. Keep this file"
        puts "  P. Preserve this file (never offer for deletion again)"
        print "Enter your choice ([D]elete/[K]eep/[P]reserve, default K): "
        input = $stdin.gets
        response = input ? input.chomp.strip.downcase : "k"

        case response
        when "d"
          # Compute MD5 hash before deleting
          begin
            if @filesystem.file_exists?(file_info[:path])
              file_info[:md5] = Digest::MD5.file(file_info[:path]).hexdigest
            else
              file_info[:md5] = ""
            end
          rescue => e
            puts "Warning: Could not compute MD5 for #{file_info[:name]}: #{e.message}"
            file_info[:md5] = ""
          end

          @filesystem.delete_file(file_info[:path])
          deleted_files << file_info
          puts "🗑 Deleted #{file_info[:name]}"
        when "p"
          preserve_file(file_info[:path])
          puts "💾 Preserved #{file_info[:name]} (will not be offered for deletion again)"
        else
          puts "✅ Kept #{file_info[:name]}"
        end
      end

      if deleted_files.empty?
        puts "\nNo files were deleted. Have a great day! 👋"
      else
        save_deleted_files_list(deleted_files)
        puts "\n#{deleted_files.length} file(s) deleted successfully! 🎉"
        puts "URLs saved to retrievable downloads list."
      end

      :exit
    end

    def save_deleted_files_list(deleted_files)
      return if deleted_files.empty?

      DownloadsCleaner::Database.migrate! # Ensure DB is ready

      deleted_files.each do |file|
        # Use the pre-computed MD5 hash
        md5 = file[:md5] || ""

        file_id = DownloadsCleaner::Database.insert_deleted_file(
          name: file[:name],
          path: file[:path],
          size: file[:size],
          md5: md5,
          deleted_at: Time.now.strftime("%Y-%m-%d %H:%M:%S")
        )
        
        file[:download_urls].each do |url_info|
          DownloadsCleaner::Database.insert_download_url(
            { url: url_info[:url], accessible: url_info[:accessible], url_type: url_info[:url_type] },
            file_id,
            md5
          )
        end
      end

      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      filename = File.expand_path("~/Downloads/retrievable_downloads.#{timestamp}.md")

      content = generate_report_content(deleted_files)
      @filesystem.write_file(filename, content)

      puts "Saved URLs to: #{filename}"
      puts "Data also saved to SQLite database at: #{DownloadsCleaner::Database.db_path}"
    end

    def generate_report_content(deleted_files)
      content = []
      content << "# Retrievable Downloads - #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
      content << ""
      content << "The following files were deleted but can be retrieved from their original URLs:"
      content << ""

      deleted_files.each_with_index do |file_info, index|
        content << "## #{index + 1}. #{file_info[:name]}"
        content << ""
        content << "- **Size**: #{FileSizeFormatter.format_size(file_info[:size])}"
        if file_info[:download_urls].length == 1
          url_info = file_info[:download_urls].first
          status = url_info[:accessible] ? "accessible" : "not accessible"
          type = url_info[:url_type] == "file" ? "direct file" : "site"
          content << "- **URL**: #{url_info[:url]} (#{status}, #{type})"
        else
          content << "- **URLs**:"
          file_info[:download_urls].each_with_index do |url_info, idx|
            status = url_info[:accessible] ? "accessible" : "not accessible"
            type = url_info[:url_type] == "file" ? "direct file" : "site"
            content << "  #{idx + 1}. #{url_info[:url]} (#{status}, #{type})"
          end
        end
        content << "- **Deleted**: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
        content << ""
      end

      total_size = deleted_files.sum { |f| f[:size] }
      content << "---"
      content << "**Total space freed**: #{FileSizeFormatter.format_size(total_size)}"
      content << "**Files deleted**: #{deleted_files.length}"

      content.join("\n")
    end
    def preserve_file(file_path)
      @preserved_list.add(file_path)
    end
  end
end
