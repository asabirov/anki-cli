import Testing
@testable import AnkiNotesCore

@Test func stripHTML() {
    let html = "<h1>Hello</h1><p>World &amp; more</p>"
    let result = Flashcard.stripHTML(html)
    #expect(result == "Hello World & more")
}

@Test func stripHTMLEmpty() {
    #expect(Flashcard.stripHTML("") == "")
}

@Test func stripHTMLPlainText() {
    #expect(Flashcard.stripHTML("plain text") == "plain text")
}

@Test func stripHTMLEntities() {
    let html = "&lt;tag&gt; &quot;quoted&quot; &#39;apostrophe&#39;"
    let result = Flashcard.stripHTML(html)
    #expect(result == "<tag> \"quoted\" 'apostrophe'")
}

@Test func cardTypeDescription() {
    #expect(CardType.new.description == "new")
    #expect(CardType.learning.description == "learning")
    #expect(CardType.review.description == "review")
}

@Test func cardQueueDescription() {
    #expect(CardQueue.new.description == "new")
    #expect(CardQueue.learning.description == "learning")
    #expect(CardQueue.review.description == "review")
    #expect(CardQueue.suspended.description == "suspended")
}

@Test func noteFieldParsing() {
    let note = Note(id: 1, modelID: 1, fields: "front\u{1F}back", flashcardCount: 1)
    #expect(note.front == "front")
    #expect(note.back == "back")
    #expect(note.fieldValues == ["front", "back"])
}
