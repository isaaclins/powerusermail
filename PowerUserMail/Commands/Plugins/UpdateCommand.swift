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
    let subtitle = "Download latest version"
    let keywords = ["update", "upgrade", "version", "latest", "download", "github", "new", "release"]
    let iconSystemName = "arrow.down.circle"
    let iconColor: CommandIconColor = .green
    let shortcut = ""
    
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
    @Published var isInstalling = false
    @Published var installProgress: String = ""
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var updateAvailable = false
    
    private let repoOwner = "isaaclins"
    private let repoName = "PowerUserMail"
    private let appName = "PowerUserMail.app"
    
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
                downloadURL = URL(string: zipAsset.browserDownloadUrl)
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
        alert.informativeText = "A new version of PowerUserMail is available!\n\nCurrent: v\(currentVersion)\nLatest: v\(latestVersion)\n\nWould you like to install it now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Now")
        alert.addButton(withTitle: "Download Only")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            Task { await installUpdate() }
        case .alertSecondButtonReturn:
            downloadUpdate()
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
        NSWorkspace.shared.open(url)
    }
    
    private func openGitHubReleases() {
        let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
        NSWorkspace.shared.open(url)
    }
    
    /// Determines the best install location for the app
    /// - If running from /Applications, update in place
    /// - If running from Xcode's DerivedData/Debug, install to /Applications
    /// - Otherwise, try the current location, fallback to /Applications
    private func bestInstallLocation() -> URL {
        let currentAppURL = Bundle.main.bundleURL
        let currentDir = currentAppURL.deletingLastPathComponent().path
        
        // If already in /Applications, update in place
        if currentDir == "/Applications" {
            return URL(fileURLWithPath: "/Applications")
        }
        
        // If running from Xcode's build directory (contains DerivedData or Debug/Release)
        if currentDir.contains("DerivedData") || 
           currentDir.contains("/Debug") || 
           currentDir.contains("/Release") ||
           currentDir.contains("Xcode") {
            print("📍 Detected development environment, installing to /Applications")
            return URL(fileURLWithPath: "/Applications")
        }
        
        // Check if we can write to the current directory
        if FileManager.default.isWritableFile(atPath: currentDir) {
            return URL(fileURLWithPath: currentDir)
        }
        
        // Default to /Applications
        return URL(fileURLWithPath: "/Applications")
    }
    
    // MARK: - One-Click Install
    
    func installUpdate() async {
        guard let url = downloadURL else {
            showInstallError("No download URL available")
            return
        }
        guard !isInstalling else { return }
        isInstalling = true
        
        let progressWindow = showProgressWindow()
        
        do {
            // Download
            updateProgressWindow(progressWindow, text: "Downloading update...")
            let (tempZipURL, _) = try await URLSession.shared.download(from: url)
            
            // Extract
            updateProgressWindow(progressWindow, text: "Extracting...")
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", tempZipURL.path, "-d", tempDir.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { throw UpdateError.extractionFailed }
            
            // Find .app
            updateProgressWindow(progressWindow, text: "Locating app...")
            let extractedAppURL = try findExtractedApp(in: tempDir)
            
            // Remove quarantine
            updateProgressWindow(progressWindow, text: "Removing quarantine...")
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", extractedAppURL.path]
            xattr.standardOutput = FileHandle.nullDevice
            xattr.standardError = FileHandle.nullDevice
            try xattr.run()
            xattr.waitUntilExit()
            
            // Install - determine best install location
            let installDir = bestInstallLocation()
            updateProgressWindow(progressWindow, text: "Installing to \(installDir.path)...")
            let destinationURL = installDir.appendingPathComponent(appName)
            let backupURL = installDir.appendingPathComponent("\(appName).backup")
            
            // Ensure we can write to the directory
            guard FileManager.default.isWritableFile(atPath: installDir.path) else {
                throw UpdateError.noWritePermission(installDir.path)
            }
            
            try? FileManager.default.removeItem(at: backupURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.moveItem(at: destinationURL, to: backupURL)
            }
            try FileManager.default.moveItem(at: extractedAppURL, to: destinationURL)
            
            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: tempZipURL)
            try? FileManager.default.removeItem(at: backupURL)
            
            isInstalling = false
            closeProgressWindow(progressWindow)
            showRestartAlert(destinationURL: destinationURL)
            
        } catch {
            isInstalling = false
            closeProgressWindow(progressWindow)
            showInstallError(error.localizedDescription)
        }
    }
    
    private func findExtractedApp(in directory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        if let app = contents.first(where: { $0.pathExtension == "app" }) { return app }
        for item in contents {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let sub = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                if let app = sub.first(where: { $0.pathExtension == "app" }) { return app }
            }
        }
        throw UpdateError.appNotFound
    }
    
    private func showRestartAlert(destinationURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Installed!"
        alert.informativeText = "PowerUserMail has been updated to v\(latestVersion ?? "latest").\n\nRestart to complete the update."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            restartApp(at: destinationURL)
        }
    }
    
    private func restartApp(at appURL: URL) {
        let script = "sleep 1; open \"\(appURL.path)\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", script]
        try? proc.run()
        NSApplication.shared.terminate(nil)
    }
    
    private func showInstallError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = "Could not install the update:\n\n\(message)\n\nTry downloading manually."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Download Manually")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { downloadUpdate() }
    }
    
    private func showProgressWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Updating PowerUserMail"
        window.center()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        let prog = NSProgressIndicator(frame: NSRect(x: 20, y: 40, width: 260, height: 20))
        prog.style = .bar
        prog.isIndeterminate = true
        prog.startAnimation(nil)
        view.addSubview(prog)
        let label = NSTextField(labelWithString: "Starting...")
        label.frame = NSRect(x: 20, y: 15, width: 260, height: 20)
        label.alignment = .center
        label.identifier = NSUserInterfaceItemIdentifier("progressLabel")
        view.addSubview(label)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        return window
    }
    
    private func updateProgressWindow(_ window: NSWindow, text: String) {
        if let label = window.contentView?.subviews.first(where: { $0.identifier?.rawValue == "progressLabel" }) as? NSTextField {
            label.stringValue = text
        }
    }
    
    private func closeProgressWindow(_ window: NSWindow) { window.close() }
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
    let browserDownloadUrl: String  // snake_case converts to camelCase (not URL)
    let size: Int
    let downloadCount: Int
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleasesFound
    case httpError(Int)
    case extractionFailed
    case appNotFound
    case noWritePermission(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .noReleasesFound:
            return "No releases found. This might be a new repository."
        case .httpError(let code):
            return "GitHub API error (HTTP \(code))"
        case .extractionFailed:
            return "Failed to extract the downloaded file"
        case .appNotFound:
            return "Could not find the app in the downloaded archive"
        case .noWritePermission(let path):
            return "No write permission for \(path). Try moving the app to /Applications first."
        }
    }
}

