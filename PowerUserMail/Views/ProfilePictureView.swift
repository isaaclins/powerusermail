import SwiftUI

struct ProfilePictureView: View {
    let account: Account?
    var size: CGFloat = 32
    var showBorder: Bool = true
    
    var body: some View {
        Group {
            if let account = account {
                AsyncImage(url: account.effectiveProfilePictureURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showBorder {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            if let account = account {
                Text(initials(for: account))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
        }
    }
    
    private func initials(for account: Account) -> String {
        let name = account.displayName.isEmpty ? account.emailAddress : account.displayName
        
        // Handle email format
        let cleanName: String
        if let atIndex = name.firstIndex(of: "@") {
            cleanName = String(name[..<atIndex])
        } else {
            cleanName = name
        }
        
        let parts = cleanName
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
        
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let last = parts[1].prefix(1).uppercased()
            return "\(first)\(last)"
        } else if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        
        return "?"
    }
}

// MARK: - Sender Profile Picture (for chat bubbles)
struct SenderProfilePicture: View {
    let email: String
    var size: CGFloat = 28
    
    var body: some View {
        ZStack {
            Circle()
                .fill(colorForEmail(email))
            
            Text(initials(for: email))
                .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
    
    private func initials(for email: String) -> String {
        // Extract name from "Name <email>" format
        var name = email
        if let angleStart = email.firstIndex(of: "<") {
            name = String(email[..<angleStart]).trimmingCharacters(in: .whitespaces)
        }
        
        // If still looks like email, use local part
        if name.contains("@") {
            if let atIndex = name.firstIndex(of: "@") {
                name = String(name[..<atIndex])
            }
        }
        
        let parts = name
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
        
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let last = parts[1].prefix(1).uppercased()
            return "\(first)\(last)"
        } else if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        
        return "?"
    }
    
    private func colorForEmail(_ email: String) -> LinearGradient {
        // Generate a consistent color based on email hash
        let hash = abs(email.hashValue)
        let hue = Double(hash % 360) / 360.0
        
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.6, brightness: 0.7),
                Color(hue: hue, saturation: 0.7, brightness: 0.6)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfilePictureView(account: nil, size: 48)
        
        SenderProfilePicture(email: "john.doe@example.com")
        SenderProfilePicture(email: "Jane Smith <jane@example.com>")
        SenderProfilePicture(email: "support@company.com")
    }
    .padding()
}


