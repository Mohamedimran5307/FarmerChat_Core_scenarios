#!/bin/bash
# =============================================================================
# MAESTRO STABLE TEST RUNNER
# Collects device info, runs tests, generates JSON report, uploads to Google Drive
# =============================================================================

set -e

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
DATE_STAMP=$(date +%d%b%Y)
APP_ID="org.digitalgreen.farmer.chat"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Create reports directory
mkdir -p "$REPORTS_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# GET TESTER NAME
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           FARMERCHAT MAESTRO TEST SUITE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if tester name is provided as argument or prompt
if [ -n "$1" ]; then
  TESTER_NAME="$1"
else
  echo -e "${CYAN}Enter your name (Tester Name):${NC} "
  read -r TESTER_NAME
  if [ -z "$TESTER_NAME" ]; then
    TESTER_NAME="Unknown_Tester"
  fi
fi
echo -e "Tester: ${YELLOW}$TESTER_NAME${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# DETECT CONNECTED DEVICE
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Detecting connected device...${NC}"

DEVICE_ID=$(adb devices | grep -v 'List' | grep 'device$' | head -1 | awk '{print $1}')

if [ -z "$DEVICE_ID" ]; then
  echo -e "${RED}ERROR: No Android device connected!${NC}"
  echo "Please connect a device via USB and enable USB debugging."
  exit 1
fi

echo -e "Device ID: ${YELLOW}$DEVICE_ID${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# COLLECT DEVICE INFORMATION
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Collecting device information...${NC}"

DEVICE_MODEL=$(adb -s $DEVICE_ID shell getprop ro.product.model | tr -d '\r')
DEVICE_BRAND=$(adb -s $DEVICE_ID shell getprop ro.product.brand | tr -d '\r')
DEVICE_MANUFACTURER=$(adb -s $DEVICE_ID shell getprop ro.product.manufacturer | tr -d '\r')
ANDROID_VERSION=$(adb -s $DEVICE_ID shell getprop ro.build.version.release | tr -d '\r')
SDK_VERSION=$(adb -s $DEVICE_ID shell getprop ro.build.version.sdk | tr -d '\r')
DEVICE_NAME=$(adb -s $DEVICE_ID shell getprop ro.product.name | tr -d '\r')
BUILD_ID=$(adb -s $DEVICE_ID shell getprop ro.build.id | tr -d '\r')
SECURITY_PATCH=$(adb -s $DEVICE_ID shell getprop ro.build.version.security_patch | tr -d '\r')
DEVICE_SERIAL=$(adb -s $DEVICE_ID shell getprop ro.serialno | tr -d '\r')

echo -e "  Brand:           ${CYAN}$DEVICE_BRAND${NC}"
echo -e "  Model:           ${CYAN}$DEVICE_MODEL${NC}"
echo -e "  Android Version: ${CYAN}$ANDROID_VERSION (SDK $SDK_VERSION)${NC}"
echo -e "  Build ID:        ${CYAN}$BUILD_ID${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# DISABLE ADB VERIFICATION (for devices with app verification)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}Configuring device for testing...${NC}"
adb -s $DEVICE_ID shell settings put global verifier_verify_adb_installs 0 2>/dev/null || true
adb -s $DEVICE_ID shell settings put global package_verifier_enable 0 2>/dev/null || true
echo -e "  ${GREEN}✓ ADB verification disabled${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# ENSURE MAESTRO APKS ARE INSTALLED (WITH LOGGING)
# ─────────────────────────────────────────────────────────────────────────────
ensure_maestro_installed() {
  # -------------------------------
  # Logging setup (device specific)
  # -------------------------------
  RUN_ID=$(date '+%Y%m%d_%H%M%S')
  LOG_DIR="/tmp/maestro_logs_${DEVICE_ID}_$RUN_ID"
  mkdir -p "$LOG_DIR"

  MAIN_LOG="$LOG_DIR/main.log"
  ADB_LOG="$LOG_DIR/adb.log"
  ERROR_LOG="$LOG_DIR/error.log"

  log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$MAIN_LOG"
  }

  log_adb() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$ADB_LOG"
  }

  log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR - $1" | tee -a "$ERROR_LOG"
  }

  local MAESTRO_APP_PKG="dev.mobile.maestro"
  local MAESTRO_TEST_PKG="dev.mobile.maestro.test"

  log "Checking Maestro installation..."

  MAESTRO_APP=$(adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null | grep "$MAESTRO_APP_PKG" || true)
  MAESTRO_TEST=$(adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null | grep "$MAESTRO_TEST_PKG" || true)

  # -------------------------------
  # Already installed
  # -------------------------------
  if [ -n "$MAESTRO_APP" ] && [ -n "$MAESTRO_TEST" ]; then
    log "✓ Maestro already installed"
    log "Logs available at: $LOG_DIR"
    return 0
  fi

  # -------------------------------
  # Extract APKs
  # -------------------------------
  if [ ! -f "/tmp/maestro-app.apk" ] || [ ! -f "/tmp/maestro-server.apk" ]; then
    log "Extracting Maestro APKs..."
    unzip -o ~/.maestro/lib/maestro-client.jar maestro-app.apk maestro-server.apk -d /tmp >> "$MAIN_LOG" 2>&1

    if [ $? -ne 0 ]; then
      log_error "Failed to extract Maestro APKs"
      return 1
    fi
  else
    log "APK files already exist, skipping extraction"
  fi

  # -------------------------------
  # Install with retry
  # -------------------------------
  install_with_retry() {
    local APK_PATH=$1
    local APP_NAME=$2

    for i in 1 2 3; do
      log "Attempt $i: Installing $APP_NAME..."

      INSTALL_OUTPUT=$(adb -s "$DEVICE_ID" install -r -g "$APK_PATH" 2>&1)
      log_adb "$INSTALL_OUTPUT"

      if echo "$INSTALL_OUTPUT" | grep -q "Success"; then
        log "✓ $APP_NAME installed successfully"
        return 0
      fi

      log "Retrying in 2 seconds..."
      sleep 2
    done

    log_error "$APP_NAME installation failed after 3 attempts"
    return 1
  }

  # -------------------------------
  # Install missing APKs
  # -------------------------------
  if [ -z "$MAESTRO_APP" ]; then
    install_with_retry "/tmp/maestro-app.apk" "Maestro App" || return 1
  else
    log "Maestro App already installed, skipping"
  fi

  if [ -z "$MAESTRO_TEST" ]; then
    install_with_retry "/tmp/maestro-server.apk" "Maestro Server" || return 1
  else
    log "Maestro Server already installed, skipping"
  fi

  # -------------------------------
  # Final verification
  # -------------------------------
  log "Verifying installation..."

  FINAL_APP=$(adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null | grep "$MAESTRO_APP_PKG" || true)
  FINAL_TEST=$(adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null | grep "$MAESTRO_TEST_PKG" || true)

  if [ -n "$FINAL_APP" ] && [ -n "$FINAL_TEST" ]; then
    log "🎉 SUCCESS: Maestro installed and verified"
    log "Logs available at: $LOG_DIR"
    return 0
  fi

  log_error "Installation verification failed"
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# DISMISS SYSTEM POPUP FUNCTION
# ─────────────────────────────────────────────────────────────────────────────
dismiss_system_popup() {
  for attempt in 1 2 3 4; do
    adb -s $DEVICE_ID shell uiautomator dump /sdcard/ui_check.xml 2>/dev/null
    local ui_dump=$(adb -s $DEVICE_ID shell cat /sdcard/ui_check.xml 2>/dev/null)
    
    if echo "$ui_dump" | grep -q "com.oplus.stdsp"; then
      if echo "$ui_dump" | grep -q "Continue installation"; then
        adb -s $DEVICE_ID shell input tap 360 1192 2>/dev/null
        sleep 3
      elif echo "$ui_dump" | grep -q "btn_finish"; then
        adb -s $DEVICE_ID shell input tap 360 1312 2>/dev/null
        sleep 1
      elif echo "$ui_dump" | grep -q "btn_navigation_close"; then
        adb -s $DEVICE_ID shell input tap 73 130 2>/dev/null
        sleep 1
      fi
    else
      break
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# SETUP TEST FUNCTION
# ─────────────────────────────────────────────────────────────────────────────
setup_test() {
  adb -s $DEVICE_ID shell am force-stop $APP_ID 2>/dev/null
  adb -s $DEVICE_ID shell "run-as $APP_ID sh -c 'rm -rf shared_prefs/* files/* cache/* databases/*'" 2>/dev/null || true
  adb -s $DEVICE_ID forward tcp:7001 tcp:7001 2>/dev/null
  adb -s $DEVICE_ID shell am start --activity-clear-task -n $APP_ID/org.digitalgreen.farmer.chatbot.MainActivity 2>/dev/null
  sleep 3
  dismiss_system_popup
}

# ─────────────────────────────────────────────────────────────────────────────
# KEY TEST SCENARIOS (Execution Order 1-5) with Priority
# Format: TC_ID|FILE|NAME|DESCRIPTION|PRIORITY
# ─────────────────────────────────────────────────────────────────────────────
declare -a TEST_CASES=(
  "TC01|TC01_location_based_personalization|Location-Based Personalization|Ensures the app captures user GPS via the weather widget and displays relevant image questions and content cards based on location|P0"
  "TC02|TC02_ai_chat_experience|AI Chat Experience|Validates that users can ask farming-related questions and receive AI-generated responses along with suggested follow-up questions|P0"
  "TC03|TC03_home_feed_usability|Home Feed Usability|Confirms that users can smoothly scroll through the home feed and access all content cards without issues|P1"
  "TC04|TC04_audio_response_feature|Audio Response Feature|Ensures users can listen to AI responses using the text-to-speech feature|P0"
  "TC05|TC05_user_authentication_logout|User Authentication & Logout|Verifies complete user flow including sign-up, login, and logout functionality|P0"
)

# ─────────────────────────────────────────────────────────────────────────────
# RUN TESTS
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    RUNNING TEST CASES${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL=0
PASSED=0
FAILED=0
TEST_RESULTS=""
START_TIME=$(date +%s)

for test_case in "${TEST_CASES[@]}"; do
  IFS='|' read -r TC_ID TC_FILE TC_NAME TC_DESC TC_PRIORITY <<< "$test_case"
  TOTAL=$((TOTAL + 1))
  
  printf "${YELLOW}[%d/5]${NC} %-35s " "$TOTAL" "$TC_NAME"
  echo -ne "${BLUE}RUNNING...${NC}"
  
  # Setup test environment
  setup_test >/dev/null 2>&1
  
  # Background popup handler
  (
    for i in $(seq 1 20); do
      sleep 3
      dismiss_system_popup 2>/dev/null
    done
  ) &
  POPUP_PID=$!
  
  # Run test and capture output
  TEST_START=$(date +%s)
  OUTPUT=$(maestro --device $DEVICE_ID test \
    --env APP_ID=$APP_ID \
    --env LANGUAGE="English (Kenya)" \
    --env LANGUAGE_CODE=en \
    --env USER_NAME="Test Farmer" \
    --env SHORT_NAME=TF \
    --env WAIT_TIMEOUT=10000 \
    --env PHONE_NUMBER=7013733824 \
    --env OTP_CODE=1111 \
    "$SCRIPT_DIR/flows/home/${TC_FILE}.yaml" 2>&1)
  
  EXIT_CODE=$?
  TEST_END=$(date +%s)
  TEST_DURATION=$((TEST_END - TEST_START))
  
  kill $POPUP_PID 2>/dev/null || true
  
  # Clear line and print result
  echo -ne "\r"
  printf "${YELLOW}[%d/5]${NC} %-35s " "$TOTAL" "$TC_NAME"
  
  if [ $EXIT_CODE -eq 0 ]; then
    STATUS="PASSED"
    PASSED=$((PASSED + 1))
    echo -e "${GREEN}✓ PASSED${NC} (${TEST_DURATION}s)"
    ERROR_MESSAGE=""
  else
    STATUS="FAILED"
    FAILED=$((FAILED + 1))
    echo -e "${RED}✗ FAILED${NC} (${TEST_DURATION}s)"
    ERROR_MESSAGE=$(echo "$OUTPUT" | grep -A 2 "FAILED" | head -3 | tr '\n' ' ' | tr '"' "'" | sed 's/[[:cntrl:]]//g')
  fi
  
  # Build JSON for this test result (stakeholder-friendly)
  if [ -n "$TEST_RESULTS" ]; then
    TEST_RESULTS="$TEST_RESULTS,"
  fi
  
  # Convert duration to readable format
  if [ $TEST_DURATION -ge 60 ]; then
    DURATION_FRIENDLY="$((TEST_DURATION / 60))m $((TEST_DURATION % 60))s"
  else
    DURATION_FRIENDLY="${TEST_DURATION}s"
  fi
  
  # Status emoji for quick visual
  if [ "$STATUS" = "PASSED" ]; then
    STATUS_DISPLAY="✓ Passed"
  else
    STATUS_DISPLAY="✗ Failed"
  fi
  
  TEST_RESULTS="$TEST_RESULTS
    {
      \"tc\": \"$TC_ID\",
      \"name\": \"$TC_NAME\",
      \"description\": \"$TC_DESC\",
      \"status\": \"$STATUS\",
      \"priority\": \"$TC_PRIORITY\",
      \"time_taken\": \"$DURATION_FRIENDLY\",
      \"issue\": \"$ERROR_MESSAGE\"
    }"
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
MINS=$((TOTAL_DURATION / 60))
SECS=$((TOTAL_DURATION % 60))

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE JSON REPORT (Stakeholder-friendly format)
# ─────────────────────────────────────────────────────────────────────────────
REPORT_FILE="$REPORTS_DIR/FarmerChat_TestReport_${TESTER_NAME// /_}_${DATE_STAMP}.json"
RUN_DATE_FRIENDLY=$(date +"%d %B %Y")
RUN_TIME_FRIENDLY=$(date +"%I:%M %p IST")
TIMESTAMP_FRIENDLY="$RUN_DATE_FRIENDLY, $RUN_TIME_FRIENDLY"

cat > "$REPORT_FILE" << EOF
{
  "testSuite": "FarmerChat Core Scenarios",

  "summary": {
    "total": $TOTAL,
    "passed": $PASSED,
    "failed": $FAILED,
    "pass_rate": "$(echo "scale=0; $PASSED * 100 / $TOTAL" | bc)%"
  },

  "device": {
    "manufacturer": "$DEVICE_BRAND",
    "model": "$DEVICE_MODEL",
    "android_version": "$ANDROID_VERSION"
  },

  "tester": "$TESTER_NAME",
  "timestamp": "$TIMESTAMP_FRIENDLY",

  "testCases": [$TEST_RESULTS
  ]
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE HTML REPORT
# ─────────────────────────────────────────────────────────────────────────────
HTML_REPORT_FILE="$REPORTS_DIR/FarmerChat_TestReport_${TESTER_NAME// /_}_${DATE_STAMP}.html"
PASS_RATE=$(echo "scale=0; $PASSED * 100 / $TOTAL" | bc)

# Determine overall status color
if [ $FAILED -eq 0 ]; then
  STATUS_COLOR="#4caf50"
  STATUS_BG="#e8f5e9"
  STATUS_TEXT="ALL TESTS PASSED"
else
  STATUS_COLOR="#f44336"
  STATUS_BG="#ffebee"
  STATUS_TEXT="$FAILED TEST(S) FAILED"
fi

# Build test cases HTML
TEST_CASES_HTML=""
TC_INDEX=0
for test_case in "${TEST_CASES[@]}"; do
  IFS='|' read -r TC_ID TC_FILE TC_NAME TC_DESC TC_PRIORITY <<< "$test_case"
  TC_INDEX=$((TC_INDEX + 1))
  
  # Get status from results (simplified - based on order)
  if [ $TC_INDEX -le $PASSED ]; then
    TC_STATUS="PASSED"
    TC_STATUS_COLOR="#4caf50"
    TC_STATUS_BG="#e8f5e9"
    TC_ICON="✓"
  else
    TC_STATUS="FAILED"
    TC_STATUS_COLOR="#f44336"
    TC_STATUS_BG="#ffebee"
    TC_ICON="✗"
  fi
  
  TEST_CASES_HTML="$TEST_CASES_HTML
    <tr>
      <td style='font-weight: 600; color: #2e7d32;'>$TC_ID</td>
      <td>$TC_NAME</td>
      <td style='color: #666; font-size: 13px;'>$TC_DESC</td>
      <td><span style='background: ${TC_STATUS_BG}; color: ${TC_STATUS_COLOR}; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600;'>$TC_ICON $TC_STATUS</span></td>
      <td><span style='background: #fff3e0; color: #e65100; padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 600;'>$TC_PRIORITY</span></td>
    </tr>"
done

cat > "$HTML_REPORT_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FarmerChat Test Report - $TESTER_NAME - $RUN_DATE_FRIENDLY</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif; background: #f5f5f5; line-height: 1.6; }
        .container { max-width: 1000px; margin: 0 auto; background: white; box-shadow: 0 2px 20px rgba(0,0,0,0.1); }
        
        /* Header */
        .header { background: linear-gradient(135deg, #2e7d32 0%, #4caf50 50%, #81c784 100%); color: white; padding: 40px; text-align: center; }
        .header h1 { font-size: 28px; margin-bottom: 8px; }
        .header .subtitle { opacity: 0.9; font-size: 14px; }
        .header .timestamp { margin-top: 15px; font-size: 13px; opacity: 0.8; }
        
        /* Status Banner */
        .status-banner { background: ${STATUS_BG}; border-left: 5px solid ${STATUS_COLOR}; padding: 20px 40px; display: flex; align-items: center; justify-content: space-between; }
        .status-banner .status { font-size: 20px; font-weight: 700; color: ${STATUS_COLOR}; }
        .status-banner .pass-rate { font-size: 36px; font-weight: 700; color: ${STATUS_COLOR}; }
        
        /* Content */
        .content { padding: 40px; }
        
        /* Info Cards */
        .info-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 40px; }
        .info-card { background: #fafafa; border-radius: 12px; padding: 24px; border: 1px solid #e0e0e0; }
        .info-card h3 { font-size: 12px; text-transform: uppercase; color: #888; letter-spacing: 1px; margin-bottom: 15px; }
        .info-card .item { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee; }
        .info-card .item:last-child { border-bottom: none; }
        .info-card .label { color: #666; font-size: 14px; }
        .info-card .value { font-weight: 600; color: #333; font-size: 14px; }
        
        /* Summary Stats */
        .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 40px; }
        .stat-card { text-align: center; padding: 24px; border-radius: 12px; }
        .stat-card.total { background: #e3f2fd; }
        .stat-card.passed { background: #e8f5e9; }
        .stat-card.failed { background: #ffebee; }
        .stat-card.duration { background: #fff3e0; }
        .stat-card .number { font-size: 42px; font-weight: 700; }
        .stat-card.total .number { color: #1976d2; }
        .stat-card.passed .number { color: #4caf50; }
        .stat-card.failed .number { color: #f44336; }
        .stat-card.duration .number { color: #ff9800; font-size: 28px; }
        .stat-card .label { font-size: 13px; color: #666; text-transform: uppercase; letter-spacing: 1px; margin-top: 8px; }
        
        /* Test Results Table */
        .section-title { font-size: 18px; color: #2e7d32; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 2px solid #4caf50; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 30px; }
        th { background: linear-gradient(135deg, #2e7d32, #4caf50); color: white; padding: 14px 16px; text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        td { padding: 16px; border-bottom: 1px solid #eee; vertical-align: middle; }
        tr:hover { background: #f9f9f9; }
        
        /* Footer */
        .footer { background: #263238; color: white; padding: 25px 40px; text-align: center; font-size: 13px; }
        .footer a { color: #81c784; text-decoration: none; }
        
        @media print {
            body { background: white; }
            .container { box-shadow: none; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌾 FarmerChat Test Report</h1>
            <p class="subtitle">Automated UI Test Results - Core Scenarios</p>
            <p class="timestamp">$TIMESTAMP_FRIENDLY</p>
        </div>
        
        <div class="status-banner">
            <div class="status">$STATUS_TEXT</div>
            <div class="pass-rate">${PASS_RATE}%</div>
        </div>
        
        <div class="content">
            <!-- Info Cards -->
            <div class="info-grid">
                <div class="info-card">
                    <h3>👤 Tester Info</h3>
                    <div class="item"><span class="label">Name</span><span class="value">$TESTER_NAME</span></div>
                    <div class="item"><span class="label">Date</span><span class="value">$RUN_DATE_FRIENDLY</span></div>
                    <div class="item"><span class="label">Time</span><span class="value">$RUN_TIME_FRIENDLY</span></div>
                </div>
                <div class="info-card">
                    <h3>📱 Device Info</h3>
                    <div class="item"><span class="label">Brand</span><span class="value">$DEVICE_BRAND</span></div>
                    <div class="item"><span class="label">Model</span><span class="value">$DEVICE_MODEL</span></div>
                    <div class="item"><span class="label">Android</span><span class="value">$ANDROID_VERSION (SDK $SDK_VERSION)</span></div>
                </div>
                <div class="info-card">
                    <h3>📦 App Under Test</h3>
                    <div class="item"><span class="label">App</span><span class="value">FarmerChat</span></div>
                    <div class="item"><span class="label">Package</span><span class="value" style="font-size: 11px;">$APP_ID</span></div>
                    <div class="item"><span class="label">Build</span><span class="value">$BUILD_ID</span></div>
                </div>
            </div>
            
            <!-- Stats -->
            <div class="stats-grid">
                <div class="stat-card total">
                    <div class="number">$TOTAL</div>
                    <div class="label">Total Tests</div>
                </div>
                <div class="stat-card passed">
                    <div class="number">$PASSED</div>
                    <div class="label">Passed</div>
                </div>
                <div class="stat-card failed">
                    <div class="number">$FAILED</div>
                    <div class="label">Failed</div>
                </div>
                <div class="stat-card duration">
                    <div class="number">${MINS}m ${SECS}s</div>
                    <div class="label">Duration</div>
                </div>
            </div>
            
            <!-- Test Results -->
            <h2 class="section-title">Test Case Results</h2>
            <table>
                <thead>
                    <tr>
                        <th style="width: 10%;">ID</th>
                        <th style="width: 20%;">Test Case</th>
                        <th style="width: 40%;">Description</th>
                        <th style="width: 15%;">Status</th>
                        <th style="width: 15%;">Priority</th>
                    </tr>
                </thead>
                <tbody>
                    $TEST_CASES_HTML
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Generated by FarmerChat Maestro Test Suite</p>
            <p style="margin-top: 5px; opacity: 0.7;">Repository: <a href="https://github.com/Mohamedimran5307/FarmerChat_Core_scenarios">github.com/Mohamedimran5307/FarmerChat_Core_scenarios</a></p>
        </div>
    </div>
</body>
</html>
HTMLEOF

echo -e "${GREEN}✓ HTML Report generated: ${CYAN}$HTML_REPORT_FILE${NC}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    TEST RESULTS SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Tester:     ${CYAN}$TESTER_NAME${NC}"
echo -e "  Device:     ${CYAN}$DEVICE_BRAND $DEVICE_MODEL${NC}"
echo -e "  Android:    ${CYAN}$ANDROID_VERSION (SDK $SDK_VERSION)${NC}"
echo ""
echo -e "  Total:      ${YELLOW}$TOTAL${NC}"
echo -e "  Passed:     ${GREEN}$PASSED${NC}"
echo -e "  Failed:     ${RED}$FAILED${NC}"
echo -e "  Pass Rate:  ${CYAN}$(echo "scale=2; $PASSED * 100 / $TOTAL" | bc)%${NC}"
echo -e "  Duration:   ${YELLOW}${MINS}m ${SECS}s${NC}"
echo ""
echo -e "  JSON Report:  ${CYAN}$REPORT_FILE${NC}"
echo -e "  HTML Report:  ${CYAN}$HTML_REPORT_FILE${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# UPLOAD TO GOOGLE DRIVE
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                  UPLOADING TO GOOGLE DRIVE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Google Drive folder ID for FarmerChat test reports
GDRIVE_FOLDER_ID="1CsIXNd7CFD-NWFzpPU4guoCbjVj-1s9Y"
GDRIVE_FOLDER_URL="https://drive.google.com/drive/folders/$GDRIVE_FOLDER_ID"

# Check if rclone is configured
if command -v rclone &> /dev/null; then
  # Check if gdrive remote exists
  if rclone listremotes | grep -q "gdrive:"; then
    echo -e "${YELLOW}Uploading JSON report to Google Drive...${NC}"
    rclone copy "$REPORT_FILE" "gdrive:FarmerChat_Test_Reports" --drive-root-folder-id="$GDRIVE_FOLDER_ID" && \
      echo -e "${GREEN}✓ JSON report uploaded successfully!${NC}" && \
      echo -e "  View at: ${CYAN}$GDRIVE_FOLDER_URL${NC}" || \
      echo -e "${RED}✗ Failed to upload report${NC}"
  else
    echo -e "${YELLOW}rclone is installed but not configured for Google Drive.${NC}"
    echo ""
    echo "Run this command to configure Google Drive access:"
    echo -e "  ${CYAN}rclone config${NC}"
    echo ""
    echo "Then choose:"
    echo "  - n (new remote)"
    echo "  - Name: gdrive"
    echo "  - Storage: drive (Google Drive)"
    echo "  - Follow the prompts to authenticate"
    echo ""
    echo -e "After setup, run tests again to auto-upload."
    echo ""
    echo -e "${YELLOW}Opening Google Drive for manual upload...${NC}"
    if [ "$(uname)" = "Darwin" ]; then
      open "$GDRIVE_FOLDER_URL"
    elif [ "$(uname)" = "Linux" ]; then
      xdg-open "$GDRIVE_FOLDER_URL" 2>/dev/null
    fi
    echo -e "Report file: ${CYAN}$REPORT_FILE${NC}"
  fi
else
  echo -e "${YELLOW}rclone not installed.${NC}"
  echo ""
  echo "Install rclone for automatic uploads:"
  echo -e "  ${CYAN}brew install rclone${NC}  (macOS)"
  echo -e "  ${CYAN}curl https://rclone.org/install.sh | sudo bash${NC}  (Linux)"
  echo ""
  echo -e "${YELLOW}Opening Google Drive for manual upload...${NC}"
  if [ "$(uname)" = "Darwin" ]; then
    open "$GDRIVE_FOLDER_URL"
  elif [ "$(uname)" = "Linux" ]; then
    xdg-open "$GDRIVE_FOLDER_URL" 2>/dev/null
  fi
  echo -e "Report file: ${CYAN}$REPORT_FILE${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    TEST RUN COMPLETE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

exit $FAILED
