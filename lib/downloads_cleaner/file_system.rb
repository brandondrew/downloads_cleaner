# frozen_string_literal: true

module DownloadsCleaner
  # File System operations
  class FileSystem
    def self.downloads_path
      File.expand_path("~/Downloads")
    end

    def self.file_exists?(path)
      File.exist?(path)
    end

    def self.directory_exists?(path)
      Dir.exist?(path)
    end

    def self.file_size(path)
      File.size(path)
    end

    def self.file_mtime(path)
      File.mtime(path)
    end

    def self.delete_file(path)
      File.delete(path)
    end

    def self.get_files_in_directory(path)
      Dir.glob("#{path}/*").select { |f| File.file?(f) }
    end

    def self.basename(path, ext = nil)
      if ext
        File.basename(path, ext)
      else
        File.basename(path)
      end
    end

    def self.write_file(path, content)
      File.open(path, "w") { |file| file.write(content) }
    end

    def self.read_file(path)
      File.read(path)
    end
  end
end
