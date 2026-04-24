import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        let mainValue = NSLocalizedString(key, bundle: .main, value: "", comment: "")
        if !mainValue.isEmpty, mainValue != key {
            return mainValue
        }

        return NSLocalizedString(key, bundle: .module, value: key, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
