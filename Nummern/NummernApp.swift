import SwiftUI

@main
struct NummernApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: NummernDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
