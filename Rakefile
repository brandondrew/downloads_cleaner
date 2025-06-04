require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
end

task :default => :test

desc "Run specific test file"
task :test_file, [:file] do |t, args|
  if args[:file]
    ruby "-Ilib test/#{args[:file]}"
  else
    puts "Usage: rake test_file[test_file_name]"
    puts "Example: rake test_file[test_deletion_md5_fixes]"
  end
end

desc "Build and install gem locally"
task :install do
  sh "gem build downloads_cleaner.gemspec"
  sh "gem install downloads_cleaner-*.gem"
end

desc "Clean up built gems"
task :clean do
  FileList["*.gem"].each { |f| File.delete(f) }
end