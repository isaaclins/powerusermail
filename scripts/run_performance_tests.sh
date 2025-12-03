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
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Parse arguments
QUICK_MODE=false
SKIP_BUILD=false
UNIT_ONLY=false
UI_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -u|--unit-only)
            UNIT_ONLY=true
            shift
            ;;
        -i|--ui-only)
            UI_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -q, --quick       Quick mode: skip clean, use cached build"
            echo "  -s, --skip-build  Skip building, run tests only"
            echo "  -u, --unit-only   Run only unit tests"
            echo "  -i, --ui-only     Run only UI tests"
            echo "  -h, --help        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="${PROJECT_DIR}/performance-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/performance_report_${TIMESTAMP}.md"
LATEST_REPORT="${REPORT_DIR}/PERFORMANCE_REPORT.md"
JSON_REPORT="${REPORT_DIR}/performance_data.json"
TARGET_MS=50

# Track test counts
TOTAL_UNIT_TESTS=20
TOTAL_UI_TESTS=13
CURRENT_TEST=0

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     PowerUserMail Performance Test Suite                 ║${NC}"
echo -e "${BLUE}║     Target: Sub-${TARGET_MS}ms for all interactions              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Expected tests: ${TOTAL_UNIT_TESTS} unit + ${TOTAL_UI_TESTS} UI = $((TOTAL_UNIT_TESTS + TOTAL_UI_TESTS)) total${NC}"
echo ""

# Create report directory
mkdir -p "${REPORT_DIR}"

# Function to run tests and capture output with live progress
run_tests() {
    local test_type=$1
    local output_file="${REPORT_DIR}/test_output_${test_type}.txt"
    
    echo -e "${YELLOW}Running ${test_type} tests...${NC}" >&2
    echo "" >&2
    
    local test_count=0
    local current_test=""
    local start_time=$(date +%s)
    
    if [ "$test_type" == "unit" ]; then
        xcodebuild test-without-building \
            -project "${PROJECT_DIR}/PowerUserMail.xcodeproj" \
            -scheme PowerUserMail \
            -destination 'platform=macOS' \
            -only-testing:PowerUserMailTests/PerformanceTests \
            -only-testing:PowerUserMailTests/LargeScalePerformanceTests \
            2>&1 | while IFS= read -r line; do
                echo "$line" >> "${output_file}"
                
                # Detect test start
                if [[ "$line" =~ "Test case '".*"' started" ]]; then
                    current_test=$(echo "$line" | sed -n "s/.*Test case '\([^']*\)'.*/\1/p" | sed 's/()//' | sed 's/.*\.//')
                    echo -e "  ${CYAN}▶${NC} Running: ${BOLD}${current_test}${NC}" >&2
                fi
                
                # Detect test pass
                if [[ "$line" =~ "' passed" ]]; then
                    test_count=$((test_count + 1))
                    test_name=$(echo "$line" | sed -n "s/.*'\([^']*\)'.*/\1/p" | sed 's/()//' | sed 's/.*\.//')
                    time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1/p')
                    echo -e "  ${GREEN}✓${NC} ${test_name} ${CYAN}(${time}s)${NC}" >&2
                fi
                
                # Detect test fail
                if [[ "$line" =~ "' failed" ]]; then
                    test_count=$((test_count + 1))
                    test_name=$(echo "$line" | sed -n "s/.*'\([^']*\)'.*/\1/p" | sed 's/()//' | sed 's/.*\.//')
                    time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1/p')
                    echo -e "  ${RED}✗${NC} ${test_name} ${CYAN}(${time}s)${NC}" >&2
                fi
            done || true
    elif [ "$test_type" == "ui" ]; then
        xcodebuild test-without-building \
            -project "${PROJECT_DIR}/PowerUserMail.xcodeproj" \
            -scheme PowerUserMail \
            -destination 'platform=macOS' \
            -only-testing:PowerUserMailUITests/PerformanceUITests \
            -only-testing:PowerUserMailUITests/PerformanceStressTests \
            2>&1 | while IFS= read -r line; do
                echo "$line" >> "${output_file}"
                
                # Detect test start
                if [[ "$line" =~ "Test case '".*"' started" ]]; then
                    current_test=$(echo "$line" | sed -n "s/.*Test case '\([^']*\)'.*/\1/p" | sed 's/()//' | sed 's/.*\.//')
                    echo -e "  ${CYAN}▶${NC} Running: ${BOLD}${current_test}${NC}" >&2
                fi
                
                # Detect test pass
                if [[ "$line" =~ "' passed" ]]; then
                    test_count=$((test_count + 1))
                    test_name=$(echo "$line" | sed -n "s/.*'\([^']*\)'.*/\1/p" | sed 's/()//' | sed 's/.*\.//')
                    time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1/p')
                    echo -e "  ${GREEN}✓${NC} ${test_name} ${CYAN}(${time}s)${NC}" >&2
                fi
                
                # Detect test fail
                if [[ "$line" =~ "' failed" ]]; then
                    test_count=$((test_count + 1))
                    test_name=$(echo "$line" | sed -n "s/.*'\([^']*\)'.*/\1/p" | sed 's/()//' | sed 's/.*\.//')
                    time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1/p')
                    echo -e "  ${RED}✗${NC} ${test_name} ${CYAN}(${time}s)${NC}" >&2
                fi
                
                # Show performance measurement when detected
                if [[ "$line" =~ "measured".*"average:" ]]; then
                    avg=$(echo "$line" | sed -n 's/.*average: \([0-9.]*\).*/\1/p')
                    if [ -n "$avg" ]; then
                        avg_ms=$(echo "$avg * 1000" | bc | cut -d'.' -f1)
                        echo -e "    ${MAGENTA}📊 Measured: ${avg_ms}ms${NC}" >&2
                    fi
                fi
            done || true
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    # Capitalize first letter (compatible with older bash)
    local test_type_cap="$(echo "${test_type:0:1}" | tr '[:lower:]' '[:upper:]')${test_type:1}"
    echo "" >&2
    echo -e "${GREEN}${test_type_cap} tests completed in ${duration}s${NC}" >&2
    
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

# Function to extract average time from test output (returns ms)
extract_avg_ms() {
    local test_name=$1
    local output_file=$2
    local avg_seconds=""
    
    # Look for measured average in the output
    avg_seconds=$(grep -E "testcase.*${test_name}.*measured.*average:" "$output_file" 2>/dev/null | \
        sed -n 's/.*average: \([0-9.]*\).*/\1/p' | head -1)
    
    # Try alternate pattern if first didn't match
    if [ -z "$avg_seconds" ]; then
        avg_seconds=$(grep -E "${test_name}.*measured.*average:" "$output_file" 2>/dev/null | \
            sed -n 's/.*average: \([0-9.]*\).*/\1/p' | head -1)
    fi
    
    if [ -n "$avg_seconds" ]; then
        # Convert to ms (multiply by 1000)
        echo "$avg_seconds" | awk '{printf "%.0f", $1 * 1000}'
    else
        echo ""
    fi
}

# Function to get status emoji based on measured vs target
get_status() {
    local measured=$1
    local target=$2
    
    if [ -z "$measured" ]; then
        echo "⏳"
    elif [ "$measured" -le "$target" ]; then
        echo "✅"
    elif [ "$measured" -le $((target * 2)) ]; then
        echo "⚠️"
    else
        echo "❌"
    fi
}

# Function to format measured value
format_measured() {
    local ms=$1
    if [ -z "$ms" ]; then
        echo "-"
    elif [ "$ms" -ge 1000 ]; then
        # Convert ms to seconds with 2 decimal places
        local secs=$(echo "scale=2; $ms / 1000" | bc)
        echo "${secs}s"
    else
        echo "${ms}ms"
    fi
}

# Function to generate markdown report
generate_report() {
    local unit_output=$1
    local ui_output=$2
    
    # Check if tests actually ran or failed
    local unit_status="🔄 Testing..."
    local ui_status="🔄 Testing..."
    local build_failed=false
    local unit_passed=0
    local unit_failed=0
    local ui_passed=0
    local ui_failed=0
    
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
        unit_passed=$(grep -c "' passed" "$unit_output" 2>/dev/null || echo "0")
        unit_failed=$(grep -c "' failed" "$unit_output" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$ui_output" ]; then
        if grep -q "TEST FAILED" "$ui_output"; then
            if grep -q "build failed\|Linker command failed\|can't write output" "$ui_output"; then
                ui_status="❌ Build Failed"
                build_failed=true
            else
                ui_status="⚠️ Some Failed"
            fi
        elif grep -q "TEST SUCCEEDED\|passed" "$ui_output"; then
            ui_status="✅ Passed"
        fi
        ui_passed=$(grep -c "' passed" "$ui_output" 2>/dev/null || echo "0")
        ui_failed=$(grep -c "' failed" "$ui_output" 2>/dev/null || echo "0")
    fi
    
    # Extract performance measurements from UI tests
    local cmd_open=$(extract_avg_ms "testCommandPaletteOpen" "$ui_output")
    local cmd_search=$(extract_avg_ms "testCommandPaletteSearch" "$ui_output")
    local cmd_nav=$(extract_avg_ms "testCommandPaletteNavigation" "$ui_output")
    local kbd_response=$(extract_avg_ms "testKeyboardShortcutResponse" "$ui_output")
    local scroll=$(extract_avg_ms "testConversationListScroll" "$ui_output")
    local filter_switch=$(extract_avg_ms "testRapidFilterSwitch" "$ui_output")
    local typing=$(extract_avg_ms "testTypingResponsiveness" "$ui_output")
    local toggle=$(extract_avg_ms "testRapidCommandPaletteToggle" "$ui_output")
    local resize=$(extract_avg_ms "testWindowResize" "$ui_output")
    local launch=$(extract_avg_ms "testAppLaunchPerformance" "$ui_output")
    local launch_interactive=$(extract_avg_ms "testAppLaunchToInteractive" "$ui_output")
    
    # Extract memory metrics
    local memory_peak=$(grep -E "Memory Peak Physical.*average:" "$ui_output" 2>/dev/null | \
        sed -n 's/.*average: \([0-9.]*\).*/\1/p' | head -1)
    local memory_peak_mb=""
    if [ -n "$memory_peak" ]; then
        memory_peak_mb=$(echo "$memory_peak" | awk '{printf "%.1f", $1 / 1024}')
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
    echo "| Test Suite | Status | Passed | Failed |" >> "${REPORT_FILE}"
    echo "|------------|--------|--------|--------|" >> "${REPORT_FILE}"
    echo "| Unit Tests | ${unit_status} | ${unit_passed} | ${unit_failed} |" >> "${REPORT_FILE}"
    echo "| UI Tests | ${ui_status} | ${ui_passed} | ${ui_failed} |" >> "${REPORT_FILE}"
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
    
    # Performance Summary Table
    echo "## 📋 Performance Summary" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo "| Metric | Target | Measured | Status |" >> "${REPORT_FILE}"
    echo "|--------|--------|----------|--------|" >> "${REPORT_FILE}"
    echo "| App Launch | 1000ms | $(format_measured "$launch") | $(get_status "$launch" 1000) |" >> "${REPORT_FILE}"
    echo "| Command Palette Open | 50ms | $(format_measured "$cmd_open") | $(get_status "$cmd_open" 50) |" >> "${REPORT_FILE}"
    echo "| Command Palette Search | 50ms | $(format_measured "$cmd_search") | $(get_status "$cmd_search" 50) |" >> "${REPORT_FILE}"
    echo "| Command Palette Navigation | 50ms | $(format_measured "$cmd_nav") | $(get_status "$cmd_nav" 50) |" >> "${REPORT_FILE}"
    echo "| Keyboard Shortcuts | 50ms | $(format_measured "$kbd_response") | $(get_status "$kbd_response" 50) |" >> "${REPORT_FILE}"
    echo "| Filter Tab Switch | 100ms | $(format_measured "$filter_switch") | $(get_status "$filter_switch" 100) |" >> "${REPORT_FILE}"
    echo "| Typing Responsiveness | 50ms | $(format_measured "$typing") | $(get_status "$typing" 50) |" >> "${REPORT_FILE}"
    echo "| Window Resize | 50ms | $(format_measured "$resize") | $(get_status "$resize" 50) |" >> "${REPORT_FILE}"
    if [ -n "$memory_peak_mb" ]; then
        echo "| Memory (Peak) | 150MB | ${memory_peak_mb}MB | $([ "$(echo "$memory_peak_mb < 150" | bc)" -eq 1 ] && echo "✅" || echo "⚠️") |" >> "${REPORT_FILE}"
    fi
    echo "" >> "${REPORT_FILE}"
    
    # Stress Test Results
    echo "## 🔥 Stress Test Results" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo "| Test | Measured | Notes |" >> "${REPORT_FILE}"
    echo "|------|----------|-------|" >> "${REPORT_FILE}"
    echo "| Rapid Command Palette Toggle (10x) | $(format_measured "$toggle") | Per 10 toggles |" >> "${REPORT_FILE}"
    echo "| Rapid Filter Switch (10x) | $(format_measured "$filter_switch") | Per 10 switches |" >> "${REPORT_FILE}"
    echo "| Conversation List Scroll | $(format_measured "$scroll") | Full scroll cycle |" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    
    echo "## 🧪 Unit Test Results" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"

    # Add unit test results as a table
    if [ -f "$unit_output" ]; then
        echo "| Test | Time | Status |" >> "${REPORT_FILE}"
        echo "|------|------|--------|" >> "${REPORT_FILE}"
        # Use process substitution to avoid subshell issue
        while IFS= read -r line; do
            test_name=$(echo "$line" | sed -n "s/.*Test case '\([^']*\)'.*/\1/p" | sed 's/()//')
            time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1s/p')
            if [ -n "$test_name" ] && [ -n "$time" ]; then
                echo "| ${test_name} | ${time} | ✅ |" >> "${REPORT_FILE}"
            fi
        done < <(grep -E "Test case '.*\(\)' passed" "$unit_output" 2>/dev/null)
        
        while IFS= read -r line; do
            test_name=$(echo "$line" | sed -n "s/.*Test case '\([^']*\)'.*/\1/p" | sed 's/()//')
            time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1s/p')
            if [ -n "$test_name" ] && [ -n "$time" ]; then
                echo "| ${test_name} | ${time} | ❌ |" >> "${REPORT_FILE}"
            fi
        done < <(grep -E "Test case '.*\(\)' failed" "$unit_output" 2>/dev/null)
    else
        echo "No unit test output file found." >> "${REPORT_FILE}"
    fi
    
    echo "" >> "${REPORT_FILE}"
    echo "## 🖥️ UI Test Results" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    
    # Add UI test results as a table
    if [ -f "$ui_output" ]; then
        echo "| Test | Time | Status |" >> "${REPORT_FILE}"
        echo "|------|------|--------|" >> "${REPORT_FILE}"
        while IFS= read -r line; do
            test_name=$(echo "$line" | sed -n "s/.*Test case '\([^']*\)'.*/\1/p" | sed 's/()//')
            time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1s/p')
            if [ -n "$test_name" ] && [ -n "$time" ]; then
                echo "| ${test_name} | ${time} | ✅ |" >> "${REPORT_FILE}"
            fi
        done < <(grep -E "Test case '.*\(\)' passed" "$ui_output" 2>/dev/null)
        
        while IFS= read -r line; do
            test_name=$(echo "$line" | sed -n "s/.*Test case '\([^']*\)'.*/\1/p" | sed 's/()//')
            time=$(echo "$line" | sed -n 's/.* (\([0-9.]*\) seconds)/\1s/p')
            if [ -n "$test_name" ] && [ -n "$time" ]; then
                echo "| ${test_name} | ${time} | ❌ |" >> "${REPORT_FILE}"
            fi
        done < <(grep -E "Test case '.*\(\)' failed" "$ui_output" 2>/dev/null)
    else
        echo "No UI test output file found." >> "${REPORT_FILE}"
    fi
    
    echo "" >> "${REPORT_FILE}"
    
    # Recommendations based on actual results
    echo "## 🔧 Optimization Recommendations" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    
    local has_recommendations=false
    
    if [ -n "$cmd_open" ] && [ "$cmd_open" -gt 50 ]; then
        echo "1. **Command Palette Open (${cmd_open}ms)** - Consider lazy loading command list or caching" >> "${REPORT_FILE}"
        has_recommendations=true
    fi
    
    if [ -n "$cmd_search" ] && [ "$cmd_search" -gt 50 ]; then
        echo "2. **Command Search (${cmd_search}ms)** - Optimize fuzzy search algorithm or add debouncing" >> "${REPORT_FILE}"
        has_recommendations=true
    fi
    
    if [ -n "$typing" ] && [ "$typing" -gt 50 ]; then
        echo "3. **Typing Responsiveness (${typing}ms)** - Reduce text field update overhead" >> "${REPORT_FILE}"
        has_recommendations=true
    fi
    
    if [ -n "$scroll" ] && [ "$scroll" -gt 1000 ]; then
        echo "4. **List Scrolling (${scroll}ms)** - Implement cell recycling or virtualization" >> "${REPORT_FILE}"
        has_recommendations=true
    fi
    
    if [ "$has_recommendations" = false ]; then
        echo "✨ All metrics within acceptable ranges!" >> "${REPORT_FILE}"
    fi
    
    echo "" >> "${REPORT_FILE}"
    echo "---" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo "*Report generated by PowerUserMail Performance Test Suite*" >> "${REPORT_FILE}"

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
START_TIME=$(date +%s)

# Show mode
if [ "$QUICK_MODE" = true ]; then
    echo -e "${MAGENTA}🚀 QUICK MODE: Skipping clean, using cached build${NC}"
    echo ""
fi

STEP=1
TOTAL_STEPS=6

# Adjust steps based on options
if [ "$QUICK_MODE" = true ] || [ "$SKIP_BUILD" = true ]; then
    TOTAL_STEPS=$((TOTAL_STEPS - 2))
fi
if [ "$UNIT_ONLY" = true ] || [ "$UI_ONLY" = true ]; then
    TOTAL_STEPS=$((TOTAL_STEPS - 1))
fi

# Step 1: Clean (skip in quick mode)
if [ "$QUICK_MODE" != true ] && [ "$SKIP_BUILD" != true ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Step ${STEP}/${TOTAL_STEPS}: Cleaning DerivedData...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    clean_derived_data
    STEP=$((STEP + 1))
    echo ""
fi

# Step 2: Build (skip in quick mode or skip-build)
if [ "$QUICK_MODE" != true ] && [ "$SKIP_BUILD" != true ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Step ${STEP}/${TOTAL_STEPS}: Building project and test targets...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}This may take 1-2 minutes...${NC}"
    xcodebuild build-for-testing \
        -project "${PROJECT_DIR}/PowerUserMail.xcodeproj" \
        -scheme PowerUserMail \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGN_STYLE=Automatic \
        2>&1 | grep -E "(error:|warning:|BUILD|Signing|Compiling|Linking)" || true
    echo -e "${GREEN}Build complete${NC}"
    STEP=$((STEP + 1))
    echo ""
fi

# Step 3: Prepare environment
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step ${STEP}/${TOTAL_STEPS}: Preparing test environment...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
clear_quarantine_and_sign
STEP=$((STEP + 1))

# Step 4: Unit tests
if [ "$UI_ONLY" != true ]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Step ${STEP}/${TOTAL_STEPS}: Running unit tests (${TOTAL_UNIT_TESTS} tests)...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Expected time: ~30 seconds${NC}"
    UNIT_OUTPUT=$(run_tests "unit")
    STEP=$((STEP + 1))
else
    UNIT_OUTPUT=""
fi

# Step 5: UI tests
if [ "$UNIT_ONLY" != true ]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Step ${STEP}/${TOTAL_STEPS}: Running UI tests (${TOTAL_UI_TESTS} tests)...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Expected time: ~5-7 minutes (includes 10x measure iterations)${NC}"
    UI_OUTPUT=$(run_tests "ui")
    STEP=$((STEP + 1))
else
    UI_OUTPUT=""
fi

# Step 6: Generate report
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step ${STEP}/${TOTAL_STEPS}: Generating report...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
generate_report "$UNIT_OUTPUT" "$UI_OUTPUT"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Performance testing complete!                        ║${NC}"
printf "${GREEN}║     Total time: %dm %02ds                                   ║${NC}\n" $MINUTES $SECONDS
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "View the report: ${BLUE}${LATEST_REPORT}${NC}"
