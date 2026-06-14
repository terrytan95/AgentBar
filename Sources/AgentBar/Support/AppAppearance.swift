import SwiftUI

enum AppAppearance {
    static func colorScheme(useDarkAppearance: Bool) -> ColorScheme {
        useDarkAppearance ? .dark : .light
    }
}
