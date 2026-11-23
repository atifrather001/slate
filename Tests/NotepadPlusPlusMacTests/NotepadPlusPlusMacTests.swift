import XCTest
@testable import NotepadPlusPlusMac

// The macro test is in Parked/Tests until the macro module returns.
@MainActor
final class NotepadPlusPlusMacTests: XCTestCase {
    func testAppStateCreation() {
        let appState = AppState()
        let initialCount = appState.documents.count
        
        appState.createNewDocument()
        
        let newCount = appState.documents.count
        XCTAssertEqual(newCount, initialCount + 1)
        XCTAssertNotNil(appState.activeDocument)
    }
    
    func testDocumentModification() {
        let appState = AppState()
        appState.createNewDocument()
        let docID = appState.activeDocumentID!
        
        appState.updateContent(for: docID, newContent: "Hello, World!")
        
        let document = appState.documents[docID]
        XCTAssertEqual(document?.content, "Hello, World!")
        XCTAssertTrue(document?.isModified ?? false)
    }
    
    func testTabNavigation() {
        let appState = AppState()
        appState.createNewDocument() // doc1
        let doc1ID = appState.activeDocumentID!
        appState.createNewDocument() // doc2
        let doc2ID = appState.activeDocumentID!
        appState.createNewDocument() // doc3
        
        appState.selectPreviousTab()
        XCTAssertEqual(appState.activeDocumentID, doc2ID)
        
        appState.selectPreviousTab()
        XCTAssertEqual(appState.activeDocumentID, doc1ID)
        
        appState.selectNextTab()
        XCTAssertEqual(appState.activeDocumentID, doc2ID)
    }
    
    func testFindReplace() {
        let appState = AppState()
        appState.createNewDocument()
        let docID = appState.activeDocumentID!
        
        appState.updateContent(for: docID, newContent: "Hello World\nHello Swift\nHello Mac")
        appState.updateSelection(for: docID, to: NSRange(location: 0, length: 0))
        
        appState.findText = "Hello"
        appState.findNext()
        
        let document = appState.documents[docID]
        XCTAssertEqual(document?.selectionRange.location, 0)
        XCTAssertEqual(document?.selectionRange.length, 5)
        
        appState.findNext()
        let document2 = appState.documents[docID]
        XCTAssertEqual(document2?.selectionRange.location, 12)
    }
    
    func testReplaceAll() {
        let appState = AppState()
        appState.createNewDocument()
        let docID = appState.activeDocumentID!
        
        appState.updateContent(for: docID, newContent: "foo bar foo baz")
        appState.findText = "foo"
        appState.replaceText = "qux"
        appState.replaceAll()
        
        let document = appState.documents[docID]
        XCTAssertEqual(document?.content, "qux bar qux baz")
    }
    
    func testLanguageDetection() {
        XCTAssertEqual(Language.from(fileExtension: "swift"), .swift)
        XCTAssertEqual(Language.from(fileExtension: "py"), .python)
        XCTAssertEqual(Language.from(fileExtension: "js"), .javascript)
        XCTAssertEqual(Language.from(fileExtension: "ts"), .typescript)
        XCTAssertEqual(Language.from(fileExtension: "html"), .html)
        XCTAssertEqual(Language.from(fileExtension: "css"), .css)
        XCTAssertEqual(Language.from(fileExtension: "json"), .json)
        XCTAssertEqual(Language.from(fileExtension: "md"), .markdown)
        XCTAssertEqual(Language.from(fileExtension: "rs"), .rust)
        XCTAssertEqual(Language.from(fileExtension: "go"), .go)
        XCTAssertNil(Language.from(fileExtension: "xyz"))
    }
}
