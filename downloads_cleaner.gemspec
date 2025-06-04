# frozen_string_literal: true

require_relative "lib/downloads_cleaner/version"

Gem::Specification.new do |spec|
  spec.name          = "downloads_cleaner"
  spec.version       = DownloadsCleaner::VERSION
  spec.authors       = ["Brandon Zylstra"]
  spec.email         = ["brandon.zylstra@gmail.com"]

  spec.summary       = "Clear large files out of your ~/Downloads folder without losing them"
  spec.description   = "Identify large files in your Downloads folder, check if they can be retrieved again, and delete them to save space."
  spec.homepage      = "https://github.com/brandondrew/downloads_cleaner"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.5.0"

  # spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files         = Dir.glob("{bin,lib,test}/**/*") + %w[LICENSE.txt README.md Rakefile]
  spec.bindir        = "bin"
  spec.executables   = ["downloads_cleaner"]
  spec.require_paths = ["lib"]
  spec.add_dependency "sqlite3", "~> 2.6"
  
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.0"
end
