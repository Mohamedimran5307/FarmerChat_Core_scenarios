#!/bin/bash
# =============================================================================
# MAESTRO STABLE TEST RUNNER
# Optimized for OPPO/ColorOS devices with Android 16+
# =============================================================================

DEVICE_ID="${1:-$(adb devices | grep -v 'List' | head -1 | awk '{print $1}')}"
APP_ID="org.digitalgreen.farmer.chat"
PASSED=0
FAILED=0
TOTAL=0
FAILED_TESTS=""
PASSED_TESTS=""
START_TIME=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           MAESTRO STABLE TEST SUITE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check device connection
if [ -z "$DEVICE_ID" ]; then
  echo -e "${RED}ERROR: No device connected${NC}"
  exit 1
fi

echo -e "Device: ${YELLOW}$DEVICE_ID${NC}"

# Disable OPPO ADB verification to prevent INSTALL_FAILED_VERIFICATION_FAILURE
echo -e "${YELLOW}Disabling ADB verification...${NC}"
adb -s $DEVICE_ID shell settings put global verifier_verify_adb_installs 0 2>/dev/null
adb -s $DEVICE_ID shell settings put global package_verifier_enable 0 2>/dev/null

# Dismiss OPPO installation popup
dismiss_oppo_popup() {
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

# Ensure Maestro APKs are installed
ensure_maestro_installed() {
  local MAESTRO_APP=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "dev.mobile.maestro$" || true)
  local MAESTRO_TEST=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "dev.mobile.maestro.test" || true)

  if [ -z "$MAESTRO_APP" ] || [ -z "$MAESTRO_TEST" ]; then
    echo -e "${YELLOW}Installing Maestro driver APKs...${NC}"
    cd /tmp
    unzip -o ~/.maestro/lib/maestro-client.jar maestro-app.apk maestro-server.apk 2>/dev/null
    if [ -z "$MAESTRO_APP" ]; then
      adb -s $DEVICE_ID install -r -g /tmp/maestro-app.apk &>/dev/null &
      sleep 3
      dismiss_oppo_popup
      wait
    fi
    if [ -z "$MAESTRO_TEST" ]; then
      adb -s $DEVICE_ID install -r -g /tmp/maestro-server.apk &>/dev/null &
      sleep 3
      dismiss_oppo_popup
      wait
    fi
    cd - >/dev/null
    echo -e "${GREEN}Maestro APKs installed${NC}"
  fi
}

ensure_maestro_installed
echo ""

# Setup test environment
setup_test() {
  adb -s $DEVICE_ID shell am force-stop $APP_ID 2>/dev/null
  adb -s $DEVICE_ID shell "run-as $APP_ID sh -c 'rm -rf shared_prefs/* files/* cache/* databases/*'" 2>/dev/null
  adb -s $DEVICE_ID forward tcp:7001 tcp:7001 2>/dev/null
  adb -s $DEVICE_ID shell am start --activity-clear-task -n $APP_ID/org.digitalgreen.farmer.chatbot.MainActivity 2>/dev/null
  sleep 3
  dismiss_oppo_popup
}

# Get test files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_FILES=$(find "$SCRIPT_DIR/flows/home" -name "*.yaml" -type f 2>/dev/null | sort -V)
TOTAL_TESTS=$(echo "$FLOW_FILES" | wc -l | tr -d ' ')

echo -e "Tests:  ${YELLOW}$TOTAL_TESTS${NC}"
echo ""
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
printf "%-4s %-45s %s\n" "#" "TEST CASE" "STATUS"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"

for flow in $FLOW_FILES; do
  TOTAL=$((TOTAL + 1))
  NAME=$(basename "$flow" .yaml)
  
  printf "${YELLOW}%-4s${NC} %-45s " "[$TOTAL]" "$NAME"
  echo -ne "${BLUE}RUNNING...${NC}"
  
  setup_test >/dev/null 2>&1

  # Background popup handler
  (
    for i in $(seq 1 20); do
      sleep 3
      dismiss_oppo_popup 2>/dev/null
    done
  ) &
  POPUP_PID=$!

  OUTPUT=$(maestro --device $DEVICE_ID test \
    --env APP_ID=$APP_ID \
    --env LANGUAGE="English (Kenya)" \
    --env LANGUAGE_CODE=en \
    --env USER_NAME="Test Farmer" \
    --env SHORT_NAME=TF \
    --env WAIT_TIMEOUT=10000 \
    --env PHONE_NUMBER=7013733824 \
    --env NEW_PHONE_NUMBER=7013733824 \
    --env OTP_CODE=1111 \
    "$flow" 2>&1)
  
  EXIT_CODE=$?
  kill $POPUP_PID 2>/dev/null

  echo -ne "\r"
  printf "%-4s %-45s " "[$TOTAL]" "$NAME"
  
  if [ $EXIT_CODE -eq 0 ]; then
    PASSED=$((PASSED + 1))
    PASSED_TESTS="$PASSED_TESTS $NAME"
    echo -e "${GREEN}✓ PASSED${NC}"
  else
    FAILED=$((FAILED + 1))
    FAILED_TESTS="$FAILED_TESTS $NAME"
    echo -e "${RED}✗ FAILED${NC}"
  fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINS=$((DURATION / 60))
SECS=$((DURATION % 60))

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    TEST RESULTS SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Total:    ${YELLOW}$TOTAL${NC}"
echo -e "  Passed:   ${GREEN}$PASSED${NC}"
echo -e "  Failed:   ${RED}$FAILED${NC}"
echo -e "  Duration: ${YELLOW}${MINS}m ${SECS}s${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
  echo -e "${RED}Failed Tests:${NC}"
  for t in $FAILED_TESTS; do
    echo -e "  ${RED}✗${NC} $t"
  done
  echo ""
fi

if [ $PASSED -gt 0 ]; then
  echo -e "${GREEN}Passed Tests:${NC}"
  for t in $PASSED_TESTS; do
    echo -e "  ${GREEN}✓${NC} $t"
  done
fi
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

exit $FAILED
