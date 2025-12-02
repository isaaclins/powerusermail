//
//  UpdateCommand.swift
//  PowerUserMail
//
//  Command to check for updates and download latest version from GitHub
//

import Foundation
import AppKit
import Combine

struct CheckForUpdatesCommand: CommandPlugin {
    let id = "check-for-updates"
    let title = "Check for Updates"
    let keywords = ["update", "upgrade", "version", "latest", "download", "github", "new", "release"]
    let iconSystemName = "arrow.down.circle"
    
    func execute() {
        Task {
            await UpdateManager.shared.checkForUpdates(silent: false)
        }
    }
}

// MARK: - Update Manager

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var isChecking = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var updateAvailable = false
    
    private let repoOwner = "isaaclins"
    private let repoName = "PowerUserMail"
    
    private init() {}
    
    // Get current app version
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    func checkForUpdates(silent: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        
        do {
            let release = try await fetchLatestRelease()
            
            latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            
            // Find the .zip asset
            if let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                downloadURL = URL(string: zipAsset.browserDownloadURL)
            }
            
            // Compare versions
            let current = currentVersion
            let latest = latestVersion ?? current
            
            updateAvailable = isNewerVersion(latest, than: current)
            
            if updateAvailable {
                showUpdateAlert(currentVersion: current, latestVersion: latest)
            } else if !silent {
                showUpToDateAlert()
            }
            
        } catch {
            print("❌ Failed to check for updates: \(error)")
            if !silent {
                showErrorAlert(error: error)
            }
        }
    }
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("PowerUserMail/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            throw UpdateError.noReleasesFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }
    
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        // Handle date-based versions like "2024.12.03-42"
        let newParts = new.components(separatedBy: CharacterSet(charactersIn: ".-"))
        let currentParts = current.components(separatedBy: CharacterSet(charactersIn: ".-"))
        
        for i in 0..<max(newParts.count, currentParts.count) {
            let newNum = i < newParts.count ? Int(newParts[i]) ?? 0 : 0
            let currentNum = i < currentParts.count ? Int(currentParts[i]) ?? 0 : 0
            
            if newNum > currentNum {
                return true
            } else if newNum < currentNum {
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Alerts
    
    private func showUpdateAlert(currentVersion: String, latestVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version of PowerUserMail is available!\n\nCurrent: v\(currentVersion)\nLatest: v\(latestVersion)\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            downloadUpdate()
        case .alertSecondButtonReturn:
            openGitHubReleases()
        default:
            break
        }
    }
    
    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date!"
        alert.informativeText = "PowerUserMail v\(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not check for updates.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        
        if alert.runModal() == .alertSecondButtonReturn {
            openGitHubReleases()
        }
    }
    
    // MARK: - Actions
    
    private func downloadUpdate() {
        guard let url = downloadURL else {
            openGitHubReleases()
            return
        }
        
        // Open download in browser or use NSWorkspace to download
        NSWorkspace.shared.open(url)
    }
    
    private func openGitHubReleases() {
        let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String?
    let htmlUrl: String
    let publishedAt: String?
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadURL: String
    let size: Int
    let downloadCount: Int
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleasesFound
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .noReleasesFound:
            return "No releases found. This might be a new repository."
        case .httpError(let code):
            return "GitHub API error (HTTP \(code))"
        }
    }
}

