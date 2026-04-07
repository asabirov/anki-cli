# anki-notes-cli

CLI for [Anki Notes: Flashcards Maker](https://apps.apple.com/app/anki-notes-flashcards-maker/id1503902660) — read your flashcards, search, view stats, and export from the terminal.

Works by reading the app's local SQLite database directly (read-only). No API keys or authentication required.

## Install

```bash
# Clone and build
git clone https://github.com/asabirov/anki-cli.git
cd anki-cli
swift build -c release

# Copy to PATH
cp .build/release/anki-notes-cli /usr/local/bin/
```

Requires: macOS 13+, Swift 5.9+, [Anki Notes](https://apps.apple.com/app/anki-notes-flashcards-maker/id1503902660) installed.

## Usage

```bash
# List flashcards
anki-notes-cli ls
anki-notes-cli ls --limit 10 --tag Japanese
anki-notes-cli ls --type review --sort due --asc
anki-notes-cli ls --favorites

# View a specific card
anki-notes-cli get 4687
anki-notes-cli get 4687 --raw   # show HTML content

# Search cards
anki-notes-cli search "hello"

# List tags
anki-notes-cli tags

# Deck statistics
anki-notes-cli stats

# Export
anki-notes-cli export --format json -o cards.json
anki-notes-cli export --format csv --tag Spanish -o spanish.csv
anki-notes-cli export --format tsv
```

All commands support `--json` for machine-readable output and `--db <path>` to override the database location.

## Commands

| Command  | Description                        |
|----------|------------------------------------|
| `ls`     | List flashcards with filters       |
| `get`    | View a flashcard by ID             |
| `search` | Search cards by front/back text    |
| `tags`   | List all tags with card counts     |
| `stats`  | Show deck statistics               |
| `export` | Export cards as JSON, CSV, or TSV  |

## How it works

Anki Notes stores its data in a Core Data SQLite database synced via iCloud (CloudKit). This CLI reads the local database at:

```
~/Library/Containers/maccatalyst.social.street.MemoryAssistant/
  Data/Library/Application Support/Anki Notes/Model1.sqlite
```

The database is opened in read-only mode — no risk of data corruption.

## License

MIT
