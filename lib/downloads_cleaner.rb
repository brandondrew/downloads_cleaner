# Main entry point for the Downloads Cleaner gem
require "optparse"
require "fileutils"
require "net/http"
require "uri"
require "json"
require "time"
require "tempfile"

require_relative "downloads_cleaner/version"
require_relative "downloads_cleaner/file_size_formatter"
require_relative "downloads_cleaner/file_system"
require_relative "downloads_cleaner/url_checker"
require_relative "downloads_cleaner/cleaner"
