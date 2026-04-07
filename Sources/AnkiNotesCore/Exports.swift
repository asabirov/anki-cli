import ArgumentParser
import Foundation

public struct AnkiNotesCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "anki-notes-cli",
        abstract: "CLI for Anki Notes flashcards (read-only, via local database)",
        version: "0.5.0",
        subcommands: [
            ListCards.self,
            GetCard.self,
            SearchCards.self,
            ListTags.self,
            StatsCommand.self,
            ExportCards.self,
            ExtractCommand.self,
            ImportCommand.self,
            BackupCommand.self,
            RestoreCommand.self,
        ]
    )

    public init() {}
}

/// Open the Anki Notes database, printing a clear error if not found.
public func openDatabase(path: String? = nil) throws -> AnkiDatabase {
    do {
        return try AnkiDatabase(path: path)
    } catch let error as AnkiCLIError {
        throw error
    } catch {
        throw AnkiCLIError.databaseError(error.localizedDescription)
    }
}
