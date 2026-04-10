import Foundation

struct FileEditorDocument {
    let trackedFile: RemoteTrackedFile
    var content: String = ""
    var originalContent: String = ""
    var remoteContentHash: String?
    var isLoading = false
    var errorMessage: String?
    var lastSavedAt: Date?
    var hasLoaded = false

    var isDirty: Bool {
        content != originalContent
    }

    mutating func discardChanges() {
        content = originalContent
    }
}
