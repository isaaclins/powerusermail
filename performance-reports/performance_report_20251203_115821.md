# ⚡ PowerUserMail Performance Report

> **Target:** Sub-50ms for all user interactions (2x faster than Superhuman's 100ms)

Generated: 2025-12-03T11:03:16Z

## 📊 Executive Summary

| Test Suite | Status |
|------------|--------|
| Unit Tests | ✅ Passed |
| UI Tests | ✅ Passed |

## 🧪 Unit Test Results

```
Test case 'PerformanceTests.testCommandFiltering()' passed on 'My Mac - PowerUserMail (64576)' (0.002 seconds)
Test case 'PerformanceTests.testCommandRegistryLookup()' passed on 'My Mac - PowerUserMail (64576)' (0.008 seconds)
Test case 'PerformanceTests.testConversationCreation()' passed on 'My Mac - PowerUserMail (64576)' (0.001 seconds)
Test case 'PerformanceTests.testConversationStateRead()' passed on 'My Mac - PowerUserMail (64576)' (0.001 seconds)
Test case 'PerformanceTests.testConversationStateWrite()' passed on 'My Mac - PowerUserMail (64576)' (0.004 seconds)
Test case 'PerformanceTests.testDateFormatting()' passed on 'My Mac - PowerUserMail (64576)' (0.003 seconds)
Test case 'PerformanceTests.testEmailCreation()' passed on 'My Mac - PowerUserMail (64576)' (0.000 seconds)
Test case 'PerformanceTests.testEmailParsing()' passed on 'My Mac - PowerUserMail (64576)' (0.001 seconds)
Test case 'PerformanceTests.testFilterConversations()' passed on 'My Mac - PowerUserMail (64576)' (0.001 seconds)
Test case 'PerformanceTests.testFuzzySearchCommands()' passed on 'My Mac - PowerUserMail (64576)' (0.007 seconds)
Test case 'PerformanceTests.testInitialsGeneration()' passed on 'My Mac - PowerUserMail (64576)' (0.001 seconds)
Test case 'PerformanceTests.testMuteConversation()' passed on 'My Mac - PowerUserMail (64576)' (0.002 seconds)
Test case 'PerformanceTests.testPerformanceMonitorOverhead()' passed on 'My Mac - PowerUserMail (64576)' (0.001 seconds)
Test case 'PerformanceTests.testPinConversation()' passed on 'My Mac - PowerUserMail (64576)' (0.002 seconds)
Test case 'PerformanceTests.testReportGeneration()' passed on 'My Mac - PowerUserMail (64576)' (0.009 seconds)
Test case 'PerformanceTests.testSearchConversations()' passed on 'My Mac - PowerUserMail (64576)' (0.003 seconds)
Test case 'PerformanceTests.testSortConversations()' passed on 'My Mac - PowerUserMail (64576)' (0.007 seconds)
Test case 'LargeScalePerformanceTests.testCommandSearch100Times()' passed on 'My Mac - PowerUserMail (64576)' (0.365 seconds)
Test case 'LargeScalePerformanceTests.testFilter1000Conversations()' passed on 'My Mac - PowerUserMail (64576)' (0.270 seconds)
Test case 'LargeScalePerformanceTests.testSort1000Conversations()' passed on 'My Mac - PowerUserMail (64576)' (0.363 seconds)
```

## 🖥️ UI Test Results

```
Test Case '-[PowerUserMailUITests.PerformanceStressTests testRapidCommandPaletteToggle]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:214: Test Case '-[PowerUserMailUITests.PerformanceStressTests testRapidCommandPaletteToggle]' measured [Time, seconds] average: 2.746, relative standard deviation: 6.630%, values: [2.958815, 2.793577, 3.025876, 2.555003, 2.666880, 2.897050, 2.822942, 2.761605, 2.505719, 2.470153], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceStressTests testRapidCommandPaletteToggle]' passed (29.024 seconds).
Test Case '-[PowerUserMailUITests.PerformanceStressTests testRapidFilterSwitch]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:224: Test Case '-[PowerUserMailUITests.PerformanceStressTests testRapidFilterSwitch]' measured [Time, seconds] average: 4.099, relative standard deviation: 5.933%, values: [3.869037, 3.870937, 3.930513, 4.627895, 4.232204, 3.967393, 3.892320, 4.416086, 4.091261, 4.094722], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceStressTests testRapidFilterSwitch]' passed (43.896 seconds).
Test Case '-[PowerUserMailUITests.PerformanceStressTests testTypingResponsiveness]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:244: Test Case '-[PowerUserMailUITests.PerformanceStressTests testTypingResponsiveness]' measured [Time, seconds] average: 1.105, relative standard deviation: 10.291%, values: [1.131555, 1.374185, 1.057837, 1.102239, 0.984349, 1.069115, 0.978317, 1.111597, 1.222587, 1.015108], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceStressTests testTypingResponsiveness]' passed (14.890 seconds).
Test Suite 'PerformanceStressTests' passed at 2025-12-03 12:00:11.786.
Test Case '-[PowerUserMailUITests.PerformanceUITests testAppLaunchPerformance]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:29: Test Case '-[PowerUserMailUITests.PerformanceUITests testAppLaunchPerformance]' measured [Duration (ApplicationLaunch), s] average: 0.597, relative standard deviation: 3.778%, values: [0.611911, 0.622048, 0.556598, 0.591871, 0.602964], performanceMetricID:com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationLaunch.duration, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
Test Case '-[PowerUserMailUITests.PerformanceUITests testAppLaunchPerformance]' passed (16.844 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testAppLaunchToInteractive]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:37: Test Case '-[PowerUserMailUITests.PerformanceUITests testAppLaunchToInteractive]' measured [Duration (ApplicationLaunch), s] average: 0.610, relative standard deviation: 3.257%, values: [0.603741, 0.610241, 0.586846, 0.604220, 0.646987], performanceMetricID:com.apple.dt.XCTMetric_OSSignpost-ApplicationLaunch.duration, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
Test Case '-[PowerUserMailUITests.PerformanceUITests testAppLaunchToInteractive]' passed (48.365 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteNavigation]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:90: Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteNavigation]' measured [Time, seconds] average: 0.611, relative standard deviation: 13.202%, values: [0.707101, 0.664550, 0.721497, 0.617273, 0.522415, 0.593481, 0.528741, 0.708294, 0.538625, 0.505903], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteNavigation]' passed (9.962 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteOpen]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:49: Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteOpen]' measured [Time, seconds] average: 1.333, relative standard deviation: 5.980%, values: [1.471618, 1.289016, 1.274942, 1.368494, 1.244419, 1.245261, 1.358273, 1.260446, 1.458507, 1.356311], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteOpen]' passed (15.919 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteSearch]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:71: Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteSearch]' measured [Time, seconds] average: 0.267, relative standard deviation: 15.920%, values: [0.317223, 0.253715, 0.237390, 0.308022, 0.211917, 0.272064, 0.263172, 0.223629, 0.350769, 0.236913], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceUITests testCommandPaletteSearch]' passed (6.615 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testConversationListScroll]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:139: Test Case '-[PowerUserMailUITests.PerformanceUITests testConversationListScroll]' measured [Time, seconds] average: 5.136, relative standard deviation: 1.126%, values: [5.070932, 5.116588, 5.098866, 5.191806, 5.108166, 5.231756, 5.086272, 5.238045, 5.120169, 5.100168], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceUITests testConversationListScroll]' passed (55.140 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testFilterTabSwitch]' started.
Test Case '-[PowerUserMailUITests.PerformanceUITests testFilterTabSwitch]' passed (4.521 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testKeyboardShortcutResponse]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:113: Test Case '-[PowerUserMailUITests.PerformanceUITests testKeyboardShortcutResponse]' measured [Time, seconds] average: 0.128, relative standard deviation: 37.017%, values: [0.265375, 0.134655, 0.121053, 0.117427, 0.095752, 0.107715, 0.092966, 0.126190, 0.109170, 0.109662], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:113: error: -[PowerUserMailUITests.PerformanceUITests testKeyboardShortcutResponse] : Can only record one set of metrics per test method. (NSInternalInconsistencyException)
Test Case '-[PowerUserMailUITests.PerformanceUITests testKeyboardShortcutResponse]' failed (3.798 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:183: Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' measured [Memory Peak Physical (PowerUserMail), kB] average: 74118.875, relative standard deviation: 0.543%, values: [73335.720000, 74204.072000, 74253.224000, 74318.760000, 74482.600000], performanceMetricID:com.apple.dt.XCTMetric_Memory-com.isaaclins.PowerUserMail.physical_peak, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:183: Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' measured [CPU Cycles (PowerUserMail), kC] average: 2505954.981, relative standard deviation: 21.127%, values: [3562187.957000, 2308828.558000, 2243029.390000, 2197617.477000, 2218111.523000], performanceMetricID:com.apple.dt.XCTMetric_CPU-com.isaaclins.PowerUserMail.cycles, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:183: Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' measured [CPU Time (PowerUserMail), s] average: 0.745, relative standard deviation: 21.858%, values: [1.067814, 0.691205, 0.674656, 0.633429, 0.655872], performanceMetricID:com.apple.dt.XCTMetric_CPU-com.isaaclins.PowerUserMail.time, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:183: Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' measured [Memory Physical (PowerUserMail), kB] average: 1205.862, relative standard deviation: 153.591%, values: [4866.048000, 819.200000, -32.768000, 180.224000, 196.608000], performanceMetricID:com.apple.dt.XCTMetric_Memory-com.isaaclins.PowerUserMail.physical, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:183: Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' measured [Absolute Memory Physical (PowerUserMail), kB] average: 73866.562, relative standard deviation: 0.532%, values: [73122.728000, 73941.928000, 73909.160000, 74089.384000, 74269.608000], performanceMetricID:com.apple.dt.XCTMetric_Memory-com.isaaclins.PowerUserMail.physical_absolute, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:183: Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' measured [CPU Instructions Retired (PowerUserMail), kI] average: 5247994.649, relative standard deviation: 20.818%, values: [7427239.710000, 4801729.209000, 4756609.948000, 4565387.429000, 4689006.951000], performanceMetricID:com.apple.dt.XCTMetric_CPU-com.isaaclins.PowerUserMail.instructions_retired, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
Test Case '-[PowerUserMailUITests.PerformanceUITests testMemoryFootprint]' passed (13.607 seconds).
Test Case '-[PowerUserMailUITests.PerformanceUITests testWindowResize]' started.
/Users/isaaclins/Documents/github/powerusermail/PowerUserMailUITests/PerformanceUITests.swift:169: Test Case '-[PowerUserMailUITests.PerformanceUITests testWindowResize]' measured [Time, seconds] average: 0.000, relative standard deviation: 94.959%, values: [0.000083, 0.000019, 0.000017, 0.000014, 0.000013, 0.000015, 0.000013, 0.000015, 0.000014, 0.000013], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
Test Case '-[PowerUserMailUITests.PerformanceUITests testWindowResize]' passed (2.429 seconds).
Test Suite 'PerformanceUITests' failed at 2025-12-03 12:03:09.000.
Test Suite 'PowerUserMailUITests.xctest' failed at 2025-12-03 12:03:09.002.
Test Suite 'Selected tests' failed at 2025-12-03 12:03:09.003.
Test case 'PerformanceStressTests.testRapidCommandPaletteToggle()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (29.024 seconds)
Test case 'PerformanceStressTests.testRapidFilterSwitch()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (43.896 seconds)
Test case 'PerformanceStressTests.testTypingResponsiveness()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (14.890 seconds)
Test case 'PerformanceUITests.testAppLaunchPerformance()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (16.844 seconds)
Test case 'PerformanceUITests.testAppLaunchToInteractive()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (48.365 seconds)
Test case 'PerformanceUITests.testCommandPaletteNavigation()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (9.962 seconds)
Test case 'PerformanceUITests.testCommandPaletteOpen()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (15.919 seconds)
Test case 'PerformanceUITests.testCommandPaletteSearch()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (6.615 seconds)
Test case 'PerformanceUITests.testConversationListScroll()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (55.140 seconds)
Test case 'PerformanceUITests.testFilterTabSwitch()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (4.521 seconds)
Test case 'PerformanceUITests.testKeyboardShortcutResponse()' failed on 'My Mac - PowerUserMailUITests-Runner (64606)' (3.798 seconds)
Test case 'PerformanceUITests.testMemoryFootprint()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (13.607 seconds)
Test case 'PerformanceUITests.testWindowResize()' passed on 'My Mac - PowerUserMailUITests-Runner (64606)' (2.429 seconds)
```

## 📋 Detailed Performance Breakdown

### UI Interactions

| Action | Target | Measured | Status |
|--------|--------|----------|--------|
| Click | 50ms | - | 🔄 |
| Hover | 50ms | - | 🔄 |
| Scroll | 50ms | - | 🔄 |
| Type Character | 50ms | - | 🔄 |

### Command Palette

| Action | Target | Measured | Status |
|--------|--------|----------|--------|
| Open (⌘K) | 50ms | - | 🔄 |
| Search Filter | 50ms | - | 🔄 |
| Navigate (↑/↓) | 50ms | - | 🔄 |
| Execute Command | 50ms | - | 🔄 |
| Close (Esc) | 50ms | - | 🔄 |

### Email List

| Action | Target | Measured | Status |
|--------|--------|----------|--------|
| Filter (Unread) | 50ms | - | 🔄 |
| Filter (All) | 50ms | - | 🔄 |
| Filter (Archived) | 50ms | - | 🔄 |
| Sort by Date | 50ms | - | 🔄 |
| Select Conversation | 50ms | - | 🔄 |

### State Changes

| Action | Target | Measured | Status |
|--------|--------|----------|--------|
| Mark as Read | 50ms | - | 🔄 |
| Mark as Unread | 50ms | - | 🔄 |
| Pin Conversation | 50ms | - | 🔄 |
| Archive Conversation | 50ms | - | 🔄 |
| Mute Conversation | 50ms | - | 🔄 |

### Compose/Reply

| Action | Target | Measured | Status |
|--------|--------|----------|--------|
| Open Compose (⌘N) | 50ms | - | 🔄 |
| Type in Body | 50ms | - | 🔄 |
| Add Recipient | 50ms | - | 🔄 |
| Send Email | 100ms* | - | 🔄 |

*Network operations have relaxed targets with optimistic UI

## 🔧 Optimization Recommendations

Based on the test results, here are the recommended optimizations:

1. **Pending analysis** - Run full test suite to identify bottlenecks

## 📈 Historical Comparison

| Version | Avg Response | P95 | Pass Rate |
|---------|--------------|-----|-----------|
| Current | - | - | - |
| Previous | - | - | - |

---

*Report generated by PowerUserMail Performance Test Suite*
