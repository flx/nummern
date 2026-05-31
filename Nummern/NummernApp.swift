import SwiftUI

@main
struct NummernApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { NummernDocument() }) { configuration in
            ContentView(document: configuration.document)
        }
    }
}
