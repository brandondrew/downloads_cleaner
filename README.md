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

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
```
