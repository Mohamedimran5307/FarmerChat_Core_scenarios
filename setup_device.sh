#!/bin/bash
# =============================================================================
# DEVICE SETUP SCRIPT
# Run this ONCE before running tests to install Maestro APKs on Android devices
# =============================================================================

DEVICE_ID="${1:-$(adb devices | grep -v 'List' | head -1 | awk '{print $1}')}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           MAESTRO DEVICE SETUP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -z "$DEVICE_ID" ]; then
  echo -e "${RED}ERROR: No device connected${NC}"
  exit 1
fi

echo -e "Device: ${YELLOW}$DEVICE_ID${NC}"
echo ""

# Function to dismiss system popup
dismiss_popup() {
  for attempt in 1 2 3 4 5 6 7 8; do
    sleep 2
    adb -s $DEVICE_ID shell uiautomator dump /sdcard/ui.xml 2>/dev/null
    local ui=$(adb -s $DEVICE_ID shell cat /sdcard/ui.xml 2>/dev/null)
    
    if echo "$ui" | grep -q "com.oplus.stdsp"; then
      if echo "$ui" | grep -q "Continue installation"; then
        echo -e "  ${YELLOW}→ Tapping 'Continue installation'${NC}"
        adb -s $DEVICE_ID shell input tap 360 1192
        sleep 4
      elif echo "$ui" | grep -q "btn_finish"; then
        echo -e "  ${YELLOW}→ Tapping 'Close'${NC}"
        adb -s $DEVICE_ID shell input tap 360 1312
        sleep 2
      elif echo "$ui" | grep -q "btn_navigation_close"; then
        echo -e "  ${YELLOW}→ Tapping 'Close' (top)${NC}"
        adb -s $DEVICE_ID shell input tap 73 130
        sleep 2
      fi
    else
      return 0
    fi
  done
}

# Check current Maestro packages
echo -e "${BLUE}Checking Maestro packages...${NC}"
MAESTRO_APP=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "package:dev.mobile.maestro$" || true)
MAESTRO_TEST=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "dev.mobile.maestro.test" || true)

echo -e "  dev.mobile.maestro:      $([ -n "$MAESTRO_APP" ] && echo -e "${GREEN}INSTALLED${NC}" || echo -e "${RED}MISSING${NC}")"
echo -e "  dev.mobile.maestro.test: $([ -n "$MAESTRO_TEST" ] && echo -e "${GREEN}INSTALLED${NC}" || echo -e "${RED}MISSING${NC}")"
echo ""

# Extract APKs from Maestro CLI
if [ -z "$MAESTRO_APP" ] || [ -z "$MAESTRO_TEST" ]; then
  echo -e "${BLUE}Extracting Maestro APKs...${NC}"
  cd /tmp
  unzip -o ~/.maestro/lib/maestro-client.jar maestro-app.apk maestro-server.apk 2>/dev/null
  echo -e "  ${GREEN}APKs extracted to /tmp${NC}"
  echo ""
fi

# Install dev.mobile.maestro if missing
if [ -z "$MAESTRO_APP" ]; then
  echo -e "${BLUE}Installing dev.mobile.maestro...${NC}"
  echo -e "  ${YELLOW}Watch device screen - approve popup if shown${NC}"
  adb -s $DEVICE_ID install -r -g /tmp/maestro-app.apk &
  INSTALL_PID=$!
  
  # Wait and dismiss popup
  dismiss_popup
  wait $INSTALL_PID 2>/dev/null
  
  # Verify
  if adb -s $DEVICE_ID shell pm list packages | grep -q "package:dev.mobile.maestro$"; then
    echo -e "  ${GREEN}dev.mobile.maestro installed successfully${NC}"
  else
    echo -e "  ${RED}Installation may have failed - check device${NC}"
  fi
  echo ""
fi

# Install dev.mobile.maestro.test if missing
if [ -z "$MAESTRO_TEST" ]; then
  echo -e "${BLUE}Installing dev.mobile.maestro.test...${NC}"
  echo -e "  ${YELLOW}Watch device screen - approve popup if shown${NC}"
  adb -s $DEVICE_ID install -r -g /tmp/maestro-server.apk &
  INSTALL_PID=$!
  
  # Wait and dismiss popup
  dismiss_popup
  wait $INSTALL_PID 2>/dev/null
  
  # Verify
  if adb -s $DEVICE_ID shell pm list packages | grep -q "dev.mobile.maestro.test"; then
    echo -e "  ${GREEN}dev.mobile.maestro.test installed successfully${NC}"
  else
    echo -e "  ${RED}Installation may have failed - check device${NC}"
  fi
  echo ""
fi

# Final verification
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Final Status:${NC}"
MAESTRO_APP=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "package:dev.mobile.maestro$" || true)
MAESTRO_TEST=$(adb -s $DEVICE_ID shell pm list packages 2>/dev/null | grep "dev.mobile.maestro.test" || true)

echo -e "  dev.mobile.maestro:      $([ -n "$MAESTRO_APP" ] && echo -e "${GREEN}✓ INSTALLED${NC}" || echo -e "${RED}✗ MISSING${NC}")"
echo -e "  dev.mobile.maestro.test: $([ -n "$MAESTRO_TEST" ] && echo -e "${GREEN}✓ INSTALLED${NC}" || echo -e "${RED}✗ MISSING${NC}")"

if [ -n "$MAESTRO_APP" ] && [ -n "$MAESTRO_TEST" ]; then
  echo ""
  echo -e "${GREEN}Device is ready for testing!${NC}"
  echo -e "Run: ${YELLOW}./run_tests.sh${NC}"
  exit 0
else
  echo ""
  echo -e "${RED}Some packages missing. Please approve popups on device and re-run this script.${NC}"
  exit 1
fi
