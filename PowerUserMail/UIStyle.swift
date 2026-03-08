import SwiftUI

/// Centralized visual tokens for a native-looking macOS interface.
enum UIStyle {
    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8
    static let cardStroke = Color(nsColor: .separatorColor).opacity(0.45)
    static let subtleShadow = Color.black.opacity(0.08)
    static let selectedFill = Color.accentColor.opacity(0.12)
    static let hoverFill = Color.primary.opacity(0.05)
}

struct AppBackgroundView: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()
    }
}
