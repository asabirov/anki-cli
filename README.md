# anki-notes-cli

CLI for [Anki Notes: Flashcards Maker](https://apps.apple.com/app/anki-notes-flashcards-maker/id1503902660) — manage your flashcards from the terminal: search, review stats, export, backup & restore.

Reads the app's local SQLite database. No API keys or authentication required. Every command except `restore` opens the database read-only. `restore` replaces the database, so it makes a safety copy first.

## Install

### From GitHub Releases (recommended)

```bash
curl -fsSL https://github.com/asabirov/anki-cli/releases/latest/download/anki-notes-cli-macos-universal.tar.gz | tar xz
install -m 755 anki-notes-cli ~/.local/bin/
```

### From source

```bash
git clone https://github.com/asabirov/anki-cli.git
cd anki-cli
swift build -c release
cp .build/release/anki-notes-cli ~/.local/bin/
```

Requires: macOS 13+, [Anki Notes](https://apps.apple.com/app/anki-notes-flashcards-maker/id1503902660) installed. Building from source requires Swift 5.9+.

## Usage

```bash
# Dashboard with retention, timeline, per-tag breakdown
anki-notes-cli dashboard

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

# Export
anki-notes-cli export --format json -o cards.json
anki-notes-cli export --format csv --tag Spanish -o spanish.csv

# Extract to markdown files + media
anki-notes-cli extract ./output --tag Japanese

# Backup & restore
anki-notes-cli backup                  # default: ~/.local/share/anki-notes-cli/backups/
anki-notes-cli backup ~/backup.sqlite
anki-notes-cli restore ~/backup.sqlite
```

All commands support `--db <path>` to override the database location. `dashboard`, `ls`, `get`, `search` and `tags` also support `--json` for machine-readable output.

## Commands

| Command     | Description                                          |
|-------------|------------------------------------------------------|
| `dashboard` | Stats dashboard: retention, timeline, per-tag table  |
| `ls`        | List flashcards with filters                         |
| `get`       | View a flashcard by ID                               |
| `search`    | Search cards by front, back and note text            |
| `tags`      | List all tags with card counts                       |
| `export`    | Export cards as JSON, CSV, or TSV                    |
| `extract`   | Extract cards to markdown files, media and `index.json` |
| `backup`    | Back up the database (SQLite snapshot)               |
| `restore`   | Restore the database from a backup. Quit Anki Notes first. Asks for confirmation unless you pass `--force`. |

## How it works

Anki Notes stores its data in a Core Data SQLite database synced via iCloud (CloudKit). This CLI reads the local database at:

```
~/Library/Containers/maccatalyst.social.street.MemoryAssistant/
  Data/Library/Application Support/Anki Notes/Model1.sqlite
```

Reading commands open the database in read-only mode. `restore` is the only command that writes to it. It first copies the current database to a `.pre-restore-<timestamp>.bak` file next to it. It refuses to run while Anki Notes is open. Afterwards, open the app to sync the restored data to iCloud.

## License

MIT
