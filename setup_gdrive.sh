#!/bin/bash
# =============================================================================
# GOOGLE DRIVE SETUP SCRIPT
# Run this once to configure Google Drive upload for test reports
# =============================================================================

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           GOOGLE DRIVE SETUP FOR TEST REPORTS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
  echo -e "${YELLOW}Installing rclone...${NC}"
  if [ "$(uname)" = "Darwin" ]; then
    brew install rclone
  else
    curl https://rclone.org/install.sh | sudo bash
  fi
fi

echo -e "${GREEN}rclone is installed${NC}"
echo ""

# Check if already configured
if rclone listremotes 2>/dev/null | grep -q "gdrive:"; then
  echo -e "${GREEN}✓ Google Drive is already configured!${NC}"
  echo ""
  echo "You're all set. Run ./run_tests.sh to execute tests and upload reports."
  exit 0
fi

echo -e "${CYAN}Setting up Google Drive access...${NC}"
echo ""
echo "This will open a browser window for Google authentication."
echo "Please sign in with your Google account and grant access."
echo ""
echo -e "${YELLOW}Press Enter to continue...${NC}"
read

# Create rclone config for Google Drive
rclone config create gdrive drive

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Verify setup
if rclone listremotes | grep -q "gdrive:"; then
  echo -e "${GREEN}✓ Google Drive configured successfully!${NC}"
  echo ""
  echo "Test reports will be uploaded to:"
  echo -e "${CYAN}https://drive.google.com/drive/folders/1Bs15iX32PLRe_fX7-OfXofnQwL5wiwkb${NC}"
  echo ""
  echo -e "Run ${YELLOW}./run_tests.sh${NC} to execute tests and upload reports."
else
  echo -e "${YELLOW}Setup may not be complete. Please run:${NC}"
  echo -e "  ${CYAN}rclone config${NC}"
  echo ""
  echo "And follow the prompts to create a 'gdrive' remote."
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
