# Downloads Cleaner

A Ruby gem to help you clean up your Downloads folder by identifying large files that can be re-downloaded later.

## Features

- Scans your Downloads folder for large files
- Checks if files can be retrieved from their original download URLs
- Allows selective or bulk deletion of retrievable files
- Creates a report of deleted files with their download URLs for later retrieval

## Installation

Install the gem:

```bash
$ gem install downloads_cleaner
```

## Usage

### Command Line

Run the cleaner with default settings (100MB threshold):

```bash
$ downloads_cleaner
```

Specify a different size threshold:

```bash
$ downloads_cleaner 50MB  # Find files larger than 50MB
$ downloads_cleaner 1GB   # Find files larger than 1GB
```

Delete files immediately without prompting:

```bash
$ downloads_cleaner --delete
```

### Ruby API

```ruby
require 'downloads_cleaner'

# Create a new cleaner with custom options
cleaner = DownloadsCleaner::Cleaner.new(
  threshold: 50 * 1024 * 1024,  # 50MB
  mode: :prompt                 # or :delete for immediate deletion
)

# Run the cleaner
cleaner.run
```

## How It Works

1. The tool scans your macOS ~/Downloads folder for files larger than the specified size threshold
2. It examines file metadata to determine the original download URL
3. It checks if the URL is still accessible
4. It presents a list of files that can be safely deleted and retrieved later
5. You can choose to delete all files, select files individually, or cancel
6. A report of deleted files and their URLs is saved to your Downloads folder

## Requirements

- Ruby 2.5 or higher
- macOS (for extended attributes support)
- Command-line utilities: `xattr`, `xxd`, and `plutil`

## Development and Testing

### Running Tests

The gem includes comprehensive tests to ensure reliability and prevent regressions of critical bugs.

To run the core bug fix tests:

```bash
# Test MD5 computation and deletion workflow
$ ruby -Ilib test/test_deletion_md5_fixes.rb

# Test database MD5 constraints
$ ruby -Ilib test/test_database_md5_constraints.rb

# Test end-to-end integration workflow
$ ruby -Ilib test/test_integration_workflow.rb
```

To run all tests:

```bash
$ rake test
```

### Critical Bug Fixes

Version 0.1.2 includes important fixes for:

1. **MD5 Computation Bug**: Previously, MD5 hashes were computed AFTER file deletion, causing database constraint failures. Now MD5 hashes are computed before deletion.

2. **Database Constraint Issues**: Fixed `NOT NULL constraint failed: download_urls.md5` errors by ensuring proper MD5 hash handling.

3. **Input Handling**: Improved handling of non-interactive environments where `stdin` might return `nil`.

### Test Coverage

The test suite includes:

- **Deletion Workflow Tests**: Verify MD5 computation happens before file deletion
- **Database Constraint Tests**: Ensure proper handling of MD5 values in database operations
- **Integration Workflow Tests**: End-to-end testing of the complete MD5 computation and database workflow
- **Error Handling Tests**: Verify graceful handling of file access errors and missing files
- **Input Validation Tests**: Test stdin handling in various environments

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
```
