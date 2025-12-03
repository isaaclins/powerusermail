#!/bin/bash
#
# run_performance_tests.sh
# PowerUserMail
#
# Runs all performance tests and generates a markdown report.
# Target: Sub-50ms for all user interactions.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="${PROJECT_DIR}/performance-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/performance_report_${TIMESTAMP}.md"
LATEST_REPORT="${REPORT_DIR}/PERFORMANCE_REPORT.md"
JSON_REPORT="${REPORT_DIR}/performance_data.json"
TARGET_MS=50

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     PowerUserMail Performance Test Suite                 ║${NC}"
echo -e "${BLUE}║     Target: Sub-${TARGET_MS}ms for all interactions              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Create report directory
mkdir -p "${REPORT_DIR}"

# Function to run tests and capture output (without rebuilding)
run_tests() {
    local test_type=$1
    local output_file="${REPORT_DIR}/test_output_${test_type}.txt"
    
    echo -e "${YELLOW}Running ${test_type} tests...${NC}" >&2
    
    if [ "$test_type" == "unit" ]; then
        xcodebuild test-without-building \
            -project "${PROJECT_DIR}/PowerUserMail.xcodeproj" \
            -scheme PowerUserMail \
            -destination 'platform=macOS' \
            -only-testing:PowerUserMailTests/PerformanceTests \
            -only-testing:PowerUserMailTests/LargeScalePerformanceTests \
            2>&1 | tee "${output_file}" >&2 || true
    elif [ "$test_type" == "ui" ]; then
        xcodebuild test-without-building \
            -project "${PROJECT_DIR}/PowerUserMail.xcodeproj" \
            -scheme PowerUserMail \
            -destination 'platform=macOS' \
            -only-testing:PowerUserMailUITests/PerformanceUITests \
            -only-testing:PowerUserMailUITests/PerformanceStressTests \
            2>&1 | tee "${output_file}" >&2 || true
    fi
    
    # Return just the output file path
    echo "${output_file}"
}

# Function to parse test output and extract timing data
parse_test_results() {
    local output_file=$1
    local results=()
    
    # Parse XCTest measure results
    while IFS= read -r line; do
        # Look for measure block results
        if [[ $line =~ "measured".*"values:".*"average:" ]]; then
            # Extract test name and average time
            echo "$line"
        fi
        # Look for our custom performance output
        if [[ $line =~ ^[✅⚠️🟠❌].*:.*ms$ ]]; then
            echo "$line"
        fi
    done < "$output_file"
}

# Function to generate markdown report
generate_report() {
    local unit_output=$1
    local ui_output=$2
    
    # Check if tests actually ran or failed
    local unit_status="🔄 Testing..."
    local ui_status="🔄 Testing..."
    local build_failed=false
    
    if [ -f "$unit_output" ]; then
        if grep -q "TEST FAILED" "$unit_output"; then
            if grep -q "build failed\|Linker command failed\|can't write output" "$unit_output"; then
                unit_status="❌ Build Failed"
                build_failed=true
            else
                unit_status="❌ Tests Failed"
            fi
        elif grep -q "TEST SUCCEEDED\|passed" "$unit_output"; then
            unit_status="✅ Passed"
        fi
    fi
    
    if [ -f "$ui_output" ]; then
        if grep -q "TEST FAILED" "$ui_output"; then
            if grep -q "build failed\|Linker command failed\|can't write output" "$ui_output"; then
                ui_status="❌ Build Failed"
                build_failed=true
            else
                ui_status="❌ Tests Failed"
            fi
        elif grep -q "TEST SUCCEEDED\|passed" "$ui_output"; then
            ui_status="✅ Passed"
        fi
    fi
    
    cat > "${REPORT_FILE}" << 'HEADER'
# ⚡ PowerUserMail Performance Report

> **Target:** Sub-50ms for all user interactions (2x faster than Superhuman's 100ms)

HEADER

    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    
    # Add summary section with actual status
    echo "## 📊 Executive Summary" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo "| Test Suite | Status |" >> "${REPORT_FILE}"
    echo "|------------|--------|" >> "${REPORT_FILE}"
    echo "| Unit Tests | ${unit_status} |" >> "${REPORT_FILE}"
    echo "| UI Tests | ${ui_status} |" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    
    if [ "$build_failed" = true ]; then
        echo "### ⚠️ Build Issues Detected" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
        echo "The build failed. Common causes:" >> "${REPORT_FILE}"
        echo "- Stale DerivedData (try running the script again after clean)" >> "${REPORT_FILE}"
        echo "- File permission issues" >> "${REPORT_FILE}"
        echo "- Xcode process still running with locks on files" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
        echo "**Suggested fix:** Close Xcode completely and run the script again." >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
    fi
    
    echo "## 🧪 Unit Test Results" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"

    # Add unit test results
    if [ -f "$unit_output" ]; then
        echo '```' >> "${REPORT_FILE}"
        # More comprehensive grep pattern
        grep -E "(Test Case|passed|failed|error:|TEST SUCCEEDED|TEST FAILED|measured|average:)" "$unit_output" 2>/dev/null | head -100 >> "${REPORT_FILE}" || echo "No test results found" >> "${REPORT_FILE}"
        echo '```' >> "${REPORT_FILE}"
    else
        echo "No unit test output file found." >> "${REPORT_FILE}"
    fi
    
    echo "" >> "${REPORT_FILE}"
    echo "## 🖥️ UI Test Results" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    
    # Add UI test results
    if [ -f "$ui_output" ]; then
        echo '```' >> "${REPORT_FILE}"
        # More comprehensive grep pattern
        grep -E "(Test Case|passed|failed|error:|TEST SUCCEEDED|TEST FAILED|measured|average:)" "$ui_output" 2>/dev/null | head -100 >> "${REPORT_FILE}" || echo "No test results found" >> "${REPORT_FILE}"
        echo '```' >> "${REPORT_FILE}"
    else
        echo "No UI test output file found." >> "${REPORT_FILE}"
    fi
    
    # Add detailed breakdown
    cat >> "${REPORT_FILE}" << 'BREAKDOWN'

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
BREAKDOWN

    # Copy to latest report
    cp "${REPORT_FILE}" "${LATEST_REPORT}"
    
    echo -e "${GREEN}Report saved to: ${REPORT_FILE}${NC}"
    echo -e "${GREEN}Latest report: ${LATEST_REPORT}${NC}"
}

# Function to clean DerivedData to avoid stale build issues
clean_derived_data() {
    echo -e "${YELLOW}Cleaning DerivedData to avoid stale build issues...${NC}"
    
    local DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"
    
    # Find and remove PowerUserMail related derived data
    if [ -d "$DERIVED_DATA" ]; then
        find "$DERIVED_DATA" -maxdepth 1 -type d -name "PowerUserMail-*" -exec rm -rf {} \; 2>/dev/null || true
        echo -e "${GREEN}DerivedData cleaned${NC}"
    fi
}

# Function to clear quarantine attributes (signing is now done during build)
clear_quarantine_and_sign() {
    echo -e "${YELLOW}Clearing macOS quarantine attributes...${NC}"
    
    local DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"
    
    if [ -d "$DERIVED_DATA" ]; then
        # Find all PowerUserMail related apps and clear quarantine
        find "$DERIVED_DATA" -path "*PowerUserMail*" -name "*.app" -exec xattr -dr com.apple.quarantine {} \; 2>/dev/null || true
        echo -e "${GREEN}Quarantine attributes cleared${NC}"
    fi
}

# Main execution
echo -e "${BLUE}Step 1/6: Cleaning DerivedData...${NC}"
clean_derived_data

echo ""
echo -e "${BLUE}Step 2/6: Building project and all test targets...${NC}"
# Build everything including test targets with proper code signing
xcodebuild build-for-testing \
    -project "${PROJECT_DIR}/PowerUserMail.xcodeproj" \
    -scheme PowerUserMail \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | grep -E "(error:|warning:|BUILD|Signing)" || true

echo ""
echo -e "${BLUE}Step 3/6: Signing apps for local testing...${NC}"
clear_quarantine_and_sign

echo ""
echo -e "${BLUE}Step 4/6: Running unit performance tests...${NC}"
UNIT_OUTPUT=$(run_tests "unit")

echo ""
echo -e "${BLUE}Step 5/6: Running UI performance tests...${NC}"
UI_OUTPUT=$(run_tests "ui")

echo ""
echo -e "${BLUE}Step 6/6: Generating report...${NC}"
generate_report "$UNIT_OUTPUT" "$UI_OUTPUT"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Performance testing complete!                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "View the report: ${BLUE}${LATEST_REPORT}${NC}"
