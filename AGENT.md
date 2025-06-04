# AGENT.md - Downloads Cleaner Ruby Gem

## General Shell Interaction
- ALWAYS use Zsh.
- NEVER use Bash.
- NEVER make assumptions about file paths or ports.
- NEVER assume the Zsh configuration file is at `$HOME/.zshrc`.
- Zsh startup configuration is at `$ZDOTDIR/.zshrc`.
- NEVER assume Rails is always running on port 3000.
- Always check $PORT (using zsh!) to get the Rails port.
- NEVER assume Postgres is always running on port 5432.
- Always check $POSTGRES_PORT to get the port for PostgreSQL.

## Security
- Always follow secure development & system administration practices.
- Always use `chmod u+x` instead of `chmod +x` to limit execution to the owner.

## User Interaction
- If I tell you to do something, just do it without asking me first.
- If I ask a question but don't tell you to do anything, first just answer the question.  If it seems likely that I might want you to take action after answering the question, ask me before taking unrequested actions.


## Developer Information
- Never use non-literal placeholders such as "yourusername" or "YOUR NAME HERE".
- My GitHub username is brandondrew.
- My name is Brandon.


## Commands
- **Build gem**: `gem build downloads_cleaner.gemspec`
- **Install dependencies**: `gem install minitest webmock` (no bundle needed)
- **Run all tests**: `ruby -Itest -Ilib -r test_helper test/test_downloads_cleaner.rb`
- **Run single test file**: `ruby -Itest -Ilib -r test_helper test/test_<name>.rb`
- **Run CLI**: `ruby -Ilib bin/downloads_cleaner [options]`

## Code Style
- Use `# frozen_string_literal: true` at top of all Ruby files
- Module namespacing: `DownloadsCleaner::`
- Class methods for utility classes (e.g., `FileSystem.downloads_path`)
- Two-space indentation, snake_case for methods/variables
- Use double quotes for strings unless single quotes avoid escaping

## Testing
- Framework: Minitest with `minitest/autorun` and colored output via `minitest-reporters`
- Test files: `test/test_*.rb` pattern
- Helper: `test/test_helper.rb` with TestUtils module and Mocks
- HTTP mocking: WebMock with `WebMock.disable_net_connect!`
- Load path: `-Itest -Ilib -r test_helper` required for running tests

### Test Output
To get colored test output, install the `minitest-reporters` gem:

```sh
gem install minitest-reporters
```

Colored output is enabled by default in the test suite using the `ProgressReporter`.
No additional setup is required.

## File Structure
- Main entry: `lib/downloads_cleaner.rb` (requires all sub-modules)
- Classes: `lib/downloads_cleaner/*.rb` (version, cleaner, file_system, url_checker, etc.)
- Tests: `test/test_*.rb` with corresponding class tests
- Binary: `bin/downloads_cleaner` executable
