require "sqlite3"
require "fileutils"
require "digest"

module DownloadsCleaner
  class Database
    class << self
      attr_accessor :test_db_path
    end
    
    def self.db_path
      # Allow tests to override the database path
      return test_db_path if test_db_path
      
      # Normal production path
      home = ENV["CLEANER_HOME"] || File.expand_path("~/.config/downloads_cleaner")
      FileUtils.mkdir_p(home)
      File.join(home, "files.db")
    end

    def self.connection
      @db ||= begin
        # Configure SQLite differently for in-memory vs file-based databases
        db = SQLite3::Database.new(db_path)
        db.results_as_hash = true
        db.execute("PRAGMA foreign_keys = ON")
        
        # Only use WAL mode for file-based databases (not for in-memory)
        unless db_path == ":memory:"
          db.execute("PRAGMA journal_mode = WAL")
          db.execute("PRAGMA synchronous = NORMAL")
          db.execute("PRAGMA mmap_size = 268435456") # 256MB
        end
        
        db.execute("PRAGMA temp_store = memory")
        db
      end
    end
    
    def self.reset_connection!
      # Close the existing connection if it exists
      if @db
        @db.close rescue nil
        @db = nil
      end
    end

    def self.migrate!
      db = connection
      
      # Create deleted_files table
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS deleted_files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          path TEXT NOT NULL,
          size INTEGER NOT NULL,
          md5 TEXT NOT NULL,
          deleted_at DATETIME NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      SQL
      
      # Create download_urls table
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS download_urls (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          deleted_file_id INTEGER NOT NULL,
          url TEXT NOT NULL,
          md5 TEXT NOT NULL,
          accessible BOOLEAN NOT NULL DEFAULT 0,
          url_type TEXT NOT NULL DEFAULT 'file',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(deleted_file_id) REFERENCES deleted_files(id) ON DELETE CASCADE,
          UNIQUE(deleted_file_id, url)
        )
      SQL
      
      # Migration for preserved_files table
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS preserved_files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          added_at TEXT NOT NULL
        );
      SQL
      
      # Migrate existing download_urls table if needed
      migrate_download_urls_table!(db)
      
      # Create indexes
      db.execute("CREATE INDEX IF NOT EXISTS idx_deleted_files_md5 ON deleted_files(md5)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_deleted_files_name ON deleted_files(name)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_deleted_files_deleted_at ON deleted_files(deleted_at)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_download_urls_deleted_file_id ON download_urls(deleted_file_id)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_download_urls_url_type ON download_urls(url_type)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_download_urls_accessible ON download_urls(accessible)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_download_urls_md5 ON download_urls(md5)")
      db.execute("CREATE INDEX IF NOT EXISTS idx_download_urls_url ON download_urls(url)")
    end

    def self.migrate_download_urls_table!(db)
      # Check if md5 column exists
      columns = db.execute("PRAGMA table_info(download_urls)")
      has_md5_column = columns.any? { |col| col["name"] == "md5" }
      
      return if has_md5_column
      
      # If md5 column doesn't exist, we need to migrate the table
      puts "Migrating download_urls table to add md5 column..."
      
      # Create new table with correct schema
      db.execute(<<-SQL)
        CREATE TABLE download_urls_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          deleted_file_id INTEGER NOT NULL,
          url TEXT NOT NULL,
          md5 TEXT NOT NULL,
          accessible BOOLEAN NOT NULL DEFAULT 0,
          url_type TEXT NOT NULL DEFAULT 'file',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(deleted_file_id) REFERENCES deleted_files(id) ON DELETE CASCADE,
          UNIQUE(deleted_file_id, url)
        )
      SQL
      
      # Copy data from old table, getting md5 from deleted_files
      db.execute(<<-SQL)
        INSERT INTO download_urls_new (id, deleted_file_id, url, md5, accessible, url_type, created_at, updated_at)
        SELECT du.id, du.deleted_file_id, du.url, df.md5, du.accessible, du.url_type, du.created_at, du.updated_at
        FROM download_urls du
        JOIN deleted_files df ON du.deleted_file_id = df.id
      SQL
      
      # Drop old table and rename new one
      db.execute("DROP TABLE download_urls")
      db.execute("ALTER TABLE download_urls_new RENAME TO download_urls")
      
      puts "Migration completed."
    rescue SQLite3::Exception => e
      puts "Warning: Migration failed (#{e.message}). This may be normal for new installations."
    end

    # Preserved files CRUD
    def self.add_preserved_file(path)
      db = connection
      db.execute(
        "INSERT OR IGNORE INTO preserved_files (path, added_at) VALUES (?, ?)",
        [File.expand_path(path), Time.now.strftime("%Y-%m-%d %H:%M:%S")]
      )
    end

    def self.preserved_file_exists?(path)
      db = connection
      !!db.get_first_value("SELECT 1 FROM preserved_files WHERE path = ?", [File.expand_path(path)])
    end

    def self.all_preserved_files
      db = connection
      db.execute("SELECT path FROM preserved_files").map { |row| row["path"] }
    end

    def self.remove_preserved_file(path)
      db = connection
      db.execute("DELETE FROM preserved_files WHERE path = ?", [File.expand_path(path)])
    end

    def self.insert_deleted_file(file_data)
      db = connection
      db.execute(
        "INSERT INTO deleted_files (name, path, size, md5, deleted_at) VALUES (?, ?, ?, ?, ?)",
        [file_data[:name], file_data[:path], file_data[:size], file_data[:md5], file_data[:deleted_at]]
      )
      db.last_insert_row_id
    end

    def self.insert_download_url(url_data, deleted_file_id, md5_hash)
      db = connection
      begin
        db.execute(
          "INSERT INTO download_urls (deleted_file_id, url, md5, accessible, url_type) VALUES (?, ?, ?, ?, ?)",
          [deleted_file_id, url_data[:url], md5_hash, url_data[:accessible] ? 1 : 0, url_data[:url_type]]
        )
        db.last_insert_row_id
      rescue SQLite3::ConstraintException => e
        if e.message.include?("UNIQUE constraint failed")
          # URL already exists for this file, skip silently
          nil
        else
          raise e
        end
      end
    end

    def self.find_files_by_md5(md5_hash)
      db = connection
      db.execute(
        "SELECT * FROM deleted_files WHERE md5 = ? ORDER BY deleted_at DESC",
        [md5_hash]
      )
    end

    def self.find_file_urls(deleted_file_id)
      db = connection
      db.execute(
        "SELECT * FROM download_urls WHERE deleted_file_id = ? ORDER BY url_type, accessible DESC",
        [deleted_file_id]
      )
    end

    def self.get_statistics
      db = connection
      stats = {}
      
      # Total files and space freed
      result = db.execute("SELECT COUNT(*) as count, SUM(size) as total_size FROM deleted_files").first
      stats[:total_files] = result["count"]
      stats[:total_size_freed] = result["total_size"] || 0
      
      # URLs by type
      url_stats = db.execute(<<-SQL)
        SELECT url_type, COUNT(*) as count, 
               SUM(CASE WHEN accessible = 1 THEN 1 ELSE 0 END) as accessible_count
        FROM download_urls 
        GROUP BY url_type
      SQL
      stats[:urls_by_type] = url_stats.each_with_object({}) do |row, hash|
        hash[row["url_type"]] = {
          total: row["count"],
          accessible: row["accessible_count"]
        }
      end
      
      # Recent activity (last 30 days)
      sql_query_recent = <<-SQL
        SELECT COUNT(*) as count, SUM(size) as total_size 
        FROM deleted_files 
        WHERE deleted_at > ?
      SQL
      recent_query_result = db.execute(sql_query_recent, [Time.now - (30 * 24 * 60 * 60)])
      recent = recent_query_result.first
      
      stats[:recent_30_days] = {
        files: recent["count"],
        size: recent["total_size"] || 0
      }
      
      stats
    end

    def self.close
      @db&.close
      @db = nil
    end
    
    # For testing purposes only - completely reset the database state
    def self.reset!
      reset_connection!
      self.test_db_path = nil
    end
  end
end