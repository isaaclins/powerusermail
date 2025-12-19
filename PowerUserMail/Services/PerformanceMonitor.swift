//
//  PerformanceMonitor.swift
//  PowerUserMail
//
//  Performance monitoring for sub-50ms rule enforcement.
//  All user interactions should complete within 50ms.
//

import Foundation
import Combine
import os.signpost

// MARK: - Performance Thresholds

/// Performance targets in milliseconds
enum PerformanceThreshold {
    static let target: Double = 50.0        // Our goal: sub-50ms
    static let acceptable: Double = 100.0   // Superhuman's standard
    static let warning: Double = 200.0      // Needs optimization
    static let critical: Double = 500.0     // Unacceptable
}

// MARK: - Performance Categories

enum PerformanceCategory: String, CaseIterable, Codable {
    case uiInteraction = "UI Interaction"
    case navigation = "Navigation"
    case commandPalette = "Command Palette"
    case emailList = "Email List"
    case emailDetail = "Email Detail"
    case compose = "Compose"
    case search = "Search"
    case stateChange = "State Change"
    case network = "Network"
    case startup = "Startup"
}

// MARK: - Performance Metric

struct PerformanceMetric: Codable, Identifiable {
    let id: UUID
    let name: String
    let category: PerformanceCategory
    let durationMs: Double
    let timestamp: Date
    let passed: Bool
    let threshold: Double
    
    init(name: String, category: PerformanceCategory, durationMs: Double, threshold: Double = PerformanceThreshold.target) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.durationMs = durationMs
        self.timestamp = Date()
        self.threshold = threshold
        self.passed = durationMs <= threshold
    }
    
    var status: String {
        if durationMs <= PerformanceThreshold.target { return "✅ PASS" }
        if durationMs <= PerformanceThreshold.acceptable { return "⚠️ SLOW" }
        if durationMs <= PerformanceThreshold.warning { return "🟠 WARNING" }
        return "❌ FAIL"
    }
    
    var statusEmoji: String {
        if durationMs <= PerformanceThreshold.target { return "✅" }
        if durationMs <= PerformanceThreshold.acceptable { return "⚠️" }
        if durationMs <= PerformanceThreshold.warning { return "🟠" }
        return "❌"
    }
}

// MARK: - Performance Report

struct PerformanceReport: Codable {
    let generatedAt: Date
    let metrics: [PerformanceMetric]
    let summary: PerformanceSummary
    
    struct PerformanceSummary: Codable {
        let totalTests: Int
        let passed: Int
        let failed: Int
        let passRate: Double
        let averageMs: Double
        let p50Ms: Double
        let p95Ms: Double
        let p99Ms: Double
        let maxMs: Double
        let minMs: Double
    }
    
    init(metrics: [PerformanceMetric]) {
        self.generatedAt = Date()
        self.metrics = metrics
        
        let durations = metrics.map { $0.durationMs }.sorted()
        let passed = metrics.filter { $0.passed }.count
        
        self.summary = PerformanceSummary(
            totalTests: metrics.count,
            passed: passed,
            failed: metrics.count - passed,
            passRate: metrics.isEmpty ? 0 : Double(passed) / Double(metrics.count) * 100,
            averageMs: durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count),
            p50Ms: durations.isEmpty ? 0 : durations[durations.count / 2],
            p95Ms: durations.isEmpty ? 0 : durations[Int(Double(durations.count) * 0.95)],
            p99Ms: durations.isEmpty ? 0 : durations[Int(Double(durations.count) * 0.99)],
            maxMs: durations.max() ?? 0,
            minMs: durations.min() ?? 0
        )
    }
    
    func toMarkdown() -> String {
        var md = """
        # ⚡ PowerUserMail Performance Report
        
        > **Target:** Sub-50ms for all interactions (2x faster than Superhuman's 100ms)
        
        Generated: \(ISO8601DateFormatter().string(from: generatedAt))
        
        ## 📊 Summary
        
        | Metric | Value |
        |--------|-------|
        | Total Tests | \(summary.totalTests) |
        | Passed (≤50ms) | \(summary.passed) (\(String(format: "%.1f", summary.passRate))%) |
        | Failed (>50ms) | \(summary.failed) |
        | Average | \(String(format: "%.2f", summary.averageMs))ms |
        | P50 (Median) | \(String(format: "%.2f", summary.p50Ms))ms |
        | P95 | \(String(format: "%.2f", summary.p95Ms))ms |
        | P99 | \(String(format: "%.2f", summary.p99Ms))ms |
        | Min | \(String(format: "%.2f", summary.minMs))ms |
        | Max | \(String(format: "%.2f", summary.maxMs))ms |
        
        ## 📋 Detailed Results
        
        | Status | Category | Action | Duration | Threshold |
        |--------|----------|--------|----------|-----------|
        
        """
        
        // Group by category
        let grouped = Dictionary(grouping: metrics) { $0.category }
        
        for category in PerformanceCategory.allCases {
            guard let categoryMetrics = grouped[category] else { continue }
            
            for metric in categoryMetrics.sorted(by: { $0.durationMs > $1.durationMs }) {
                md += "| \(metric.statusEmoji) | \(category.rawValue) | \(metric.name) | \(String(format: "%.2f", metric.durationMs))ms | \(String(format: "%.0f", metric.threshold))ms |\n"
            }
        }
        
        // Add category breakdown
        md += """
        
        ## 📈 Category Breakdown
        
        | Category | Tests | Avg (ms) | Max (ms) | Pass Rate |
        |----------|-------|----------|----------|-----------|
        
        """
        
        for category in PerformanceCategory.allCases {
            guard let categoryMetrics = grouped[category] else { continue }
            let durations = categoryMetrics.map { $0.durationMs }
            let avg = durations.reduce(0, +) / Double(durations.count)
            let max = durations.max() ?? 0
            let passed = categoryMetrics.filter { $0.passed }.count
            let passRate = Double(passed) / Double(categoryMetrics.count) * 100
            
            md += "| \(category.rawValue) | \(categoryMetrics.count) | \(String(format: "%.2f", avg)) | \(String(format: "%.2f", max)) | \(String(format: "%.1f", passRate))% |\n"
        }
        
        // Add recommendations
        let slowTests = metrics.filter { $0.durationMs > PerformanceThreshold.target }.sorted { $0.durationMs > $1.durationMs }
        
        if !slowTests.isEmpty {
            md += """
            
            ## 🔧 Optimization Recommendations
            
            The following actions exceed the 50ms target and should be optimized:
            
            """
            
            for (index, metric) in slowTests.prefix(10).enumerated() {
                let priority = metric.durationMs > PerformanceThreshold.warning ? "🔴 HIGH" : "🟡 MEDIUM"
                md += "\(index + 1). **\(metric.name)** (\(metric.category.rawValue)) - \(String(format: "%.2f", metric.durationMs))ms - \(priority)\n"
            }
        } else {
            md += """
            
            ## 🎉 All Tests Pass!
            
            All measured interactions complete within the 50ms target. Great job!
            
            """
        }
        
        return md
    }
    
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Performance Monitor

@MainActor
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published private(set) var metrics: [PerformanceMetric] = []
    @Published private(set) var isEnabled: Bool = true
    
    private let signpostLog = OSLog(subsystem: "com.powerusermail", category: "Performance")
    private var activeSignposts: [String: OSSignpostID] = [:]
    
    private init() {
        #if DEBUG
        isEnabled = true
        #else
        isEnabled = ProcessInfo.processInfo.environment["PERFORMANCE_MONITORING"] == "1"
        #endif
    }
    
    // MARK: - Measurement API
    
    /// Measure a synchronous operation
    func measure<T>(
        _ name: String,
        category: PerformanceCategory,
        threshold: Double = PerformanceThreshold.target,
        operation: () -> T
    ) -> T {
        guard isEnabled else { return operation() }
        
        let start = CFAbsoluteTimeGetCurrent()
        let result = operation()
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000 // Convert to ms
        
        recordMetric(name: name, category: category, durationMs: duration, threshold: threshold)
        return result
    }
    
    /// Measure an async operation
    func measureAsync<T>(
        _ name: String,
        category: PerformanceCategory,
        threshold: Double = PerformanceThreshold.target,
        operation: () async -> T
    ) async -> T {
        guard isEnabled else { return await operation() }
        
        let start = CFAbsoluteTimeGetCurrent()
        let result = await operation()
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        
        recordMetric(name: name, category: category, durationMs: duration, threshold: threshold)
        return result
    }
    
    /// Measure an async throwing operation
    func measureAsyncThrows<T>(
        _ name: String,
        category: PerformanceCategory,
        threshold: Double = PerformanceThreshold.target,
        operation: () async throws -> T
    ) async throws -> T {
        guard isEnabled else { return try await operation() }
        
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        
        recordMetric(name: name, category: category, durationMs: duration, threshold: threshold)
        return result
    }
    
    /// Start a manual measurement
    func startMeasurement(_ name: String) {
        guard isEnabled else { return }
        let signpostID = OSSignpostID(log: signpostLog)
        activeSignposts[name] = signpostID
        os_signpost(.begin, log: signpostLog, name: "Measurement", signpostID: signpostID, "%{public}s", name)
    }
    
    /// End a manual measurement
    func endMeasurement(_ name: String, category: PerformanceCategory, threshold: Double = PerformanceThreshold.target) {
        guard isEnabled else { return }
        guard let signpostID = activeSignposts.removeValue(forKey: name) else { return }
        os_signpost(.end, log: signpostLog, name: "Measurement", signpostID: signpostID)
    }
    
    // MARK: - Recording
    
    private func recordMetric(name: String, category: PerformanceCategory, durationMs: Double, threshold: Double) {
        let metric = PerformanceMetric(
            name: name,
            category: category,
            durationMs: durationMs,
            threshold: threshold
        )
        
        metrics.append(metric)
        
        // Log warning for slow operations
        if durationMs > threshold {
            print("⚠️ SLOW: \(name) took \(String(format: "%.2f", durationMs))ms (target: \(threshold)ms)")
        }
        
        #if DEBUG
        // Always log in debug for visibility
        let status = metric.statusEmoji
        print("\(status) [\(category.rawValue)] \(name): \(String(format: "%.2f", durationMs))ms")
        #endif
    }
    
    // MARK: - Reporting
    
    func generateReport() -> PerformanceReport {
        return PerformanceReport(metrics: metrics)
    }
    
    func clearMetrics() {
        metrics.removeAll()
    }
    
    func exportReport(to url: URL) throws {
        let report = generateReport()
        let markdown = report.toMarkdown()
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Convenience Extensions

extension PerformanceMonitor {
    /// Quick measurement for UI interactions
    func measureUI(_ name: String, operation: () -> Void) {
        measure(name, category: .uiInteraction, operation: operation)
    }
    
    /// Quick measurement for navigation
    func measureNavigation(_ name: String, operation: () -> Void) {
        measure(name, category: .navigation, operation: operation)
    }
    
    /// Quick measurement for state changes
    func measureStateChange(_ name: String, operation: () -> Void) {
        measure(name, category: .stateChange, operation: operation)
    }
}

// MARK: - Test Support

#if DEBUG
extension PerformanceMonitor {
    /// Add a test metric directly (for unit testing)
    func addTestMetric(name: String, category: PerformanceCategory, durationMs: Double) {
        let metric = PerformanceMetric(name: name, category: category, durationMs: durationMs)
        metrics.append(metric)
    }
    
    /// Check if all metrics pass the threshold
    var allMetricsPass: Bool {
        metrics.allSatisfy { $0.passed }
    }
    
    /// Get metrics that failed
    var failedMetrics: [PerformanceMetric] {
        metrics.filter { !$0.passed }
    }
}
#endif



