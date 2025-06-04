# CHANGELOG

All notable changes to this project are expected to be documented in this file, ideally following the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) conventions for the most part.

---

## [Unreleased]

---

## [0.3.0] - 2025-06-04

### Added
- SQLite database integration for storing deleted file metadata at `${CLEANER_HOME:-$HOME/.config/downloads_cleaner}/files.db`
- Enhanced URL type detection using HTTP headers (`Content-Type` and `Content-Disposition`)
- MD5 hash calculation and storage for file deduplication
- Intelligent distinction between direct file download URLs and website URLs
- Visual indicators in output: 📁 for file URLs, 🌐 for site URLs
- Database statistics and querying capabilities
- Project file for project-specific aliases, functions, environment variables, etc.

### Changed
- Upgraded to sqlite3 gem ~> 2.6 (latest version with SQLite 3.49.1)
- Enhanced UrlChecker to perform HEAD requests and analyze response headers
- Improved URL type classification logic based on Content-Disposition and Content-Type
- Updated reports to include URL type information (direct file vs site)
- Better error handling for network requests with timeouts

### Fixed
- More accurate detection of downloadable files vs website links
- Replaced naive filename-based URL heuristics with proper HTTP header analysis

---

## [0.2.0] - 2025-06-04

### Fixed
- The deletion prompt is no longer shown when no files are found matching the size criteria given.

---

## [0.1.0] - 2025-06-02

### Added
- Initial release of `downloads_cleaner`.
- Scans the Downloads folder for large files.
- Identifies files that can be deleted and re-downloaded.
- Supports interactive and immediate deletion modes.
- Generates reports of deleted files and freed space.

---

[Unreleased]: https://github.com/brandondrew/downloads_cleaner/compare/0.3.0...HEAD
[0.3.0]: https://github.com/brandondrew/downloads_cleaner/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/brandondrew/downloads_cleaner/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/brandondrew/downloads_cleaner/tree/0.1.0
