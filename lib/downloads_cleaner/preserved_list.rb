# frozen_string_literal: true

module DownloadsCleaner
  # Manages the list of preserved (never delete) files using the database
  class PreservedList
    def initialize(_path = nil)
      DownloadsCleaner::Database.migrate!
    end

    def files
      DownloadsCleaner::Database.all_preserved_files
    end

    def include?(file_path)
      DownloadsCleaner::Database.preserved_file_exists?(file_path)
    end

    def add(file_path)
      DownloadsCleaner::Database.add_preserved_file(file_path)
    end

    def remove(file_path)
      DownloadsCleaner::Database.remove_preserved_file(file_path)
    end
  end
end
