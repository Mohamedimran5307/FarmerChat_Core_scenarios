# FarmerChat Maestro Test Suite

Automated UI test suite for the FarmerChat Android application using Maestro framework. Optimized for OPPO/ColorOS devices with Android 16+.

## Quick Start for Testers

### Prerequisites

1. **Android Device** connected via USB with USB Debugging enabled
2. **ADB** installed and accessible from command line
3. **Maestro CLI** installed: 
   ```bash
   curl -Ls "https://get.maestro.mobile.dev" | bash
   ```
4. **FarmerChat APK** installed on the device

### Running Tests

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Mohamedimran5307/maestro-stable.git
   cd maestro-stable
   ```

2. **Run the test suite:**
   ```bash
   ./run_tests.sh
   ```
   
   Or with your name:
   ```bash
   ./run_tests.sh "Your Name"
   ```

3. **Follow the prompts** - Enter your name when asked

4. **View Results** - JSON report will be generated in `reports/` folder

---

## Test Cases

| ID | Name | Description |
|----|------|-------------|
| TC05 | Weather Widget Location | Verifies weather widget functionality: tap weather button, grant location permission, verify weather forecast loads, and return to home screen |
| TC06 | Type Question AI Response | Tests chat flow: enter farming question, send message, wait for AI response, verify related questions appear |
| TC08 | Home Feed Scroll | Validates home feed scrolling and verifies feed cards are accessible |
| TC11 | Listen AI Response | Tests text-to-speech: ask question, receive response, tap listen button, verify audio playback |
| TC25 | Settings Logout | Complete auth flow: sign up, verify OTP, login, navigate to settings, logout |

---

## Google Drive Upload Setup

### Option 1: Using rclone (Recommended)

1. **Install rclone:**
   ```bash
   # macOS
   brew install rclone
   
   # Linux
   curl https://rclone.org/install.sh | sudo bash
   ```

2. **Configure Google Drive:**
   ```bash
   rclone config
   ```
   - Choose `n` for new remote
   - Name it `gdrive`
   - Choose `drive` (Google Drive)
   - Follow OAuth prompts

3. **Run tests** - Reports will auto-upload to `gdrive:FarmerChat_Test_Reports/`

### Option 2: Using gdrive CLI

1. **Install gdrive:**
   ```bash
   # macOS
   brew install gdrive
   
   # Linux
   # Download from https://github.com/glotlabs/gdrive/releases
   ```

2. **Authenticate:**
   ```bash
   gdrive account add
   ```

3. **Set folder ID (optional):**
   ```bash
   export GDRIVE_FOLDER_ID="your-folder-id-here"
   ```

### Option 3: Manual Upload

If no CLI tool is installed, the script will:
- Generate the JSON report locally in `reports/`
- Prompt you to open Google Drive for manual upload

---

## JSON Report Format

```json
{
  "report_metadata": {
    "report_id": "Tester_Name_20260414_153000",
    "generated_at": "2026-04-14T15:30:00"
  },
  "tester_info": {
    "tester_name": "John Doe",
    "machine_hostname": "Johns-MacBook",
    "os_type": "Darwin"
  },
  "device_info": {
    "device_id": "1a0a08f0",
    "brand": "OPPO",
    "model": "CPH2565",
    "android_version": "16",
    "sdk_version": "36"
  },
  "test_summary": {
    "total_tests": 5,
    "passed": 5,
    "failed": 0,
    "pass_rate": "100%",
    "total_duration_formatted": "8m 30s"
  },
  "test_results": [
    {
      "test_id": "TC05",
      "test_name": "Weather Widget Location",
      "description": "Verifies weather widget functionality...",
      "status": "PASSED",
      "duration_seconds": 95
    }
  ]
}
```

---

## Project Structure

```
maestro-stable/
├── run_tests.sh              # Main test runner script
├── setup_device.sh           # One-time device setup for Maestro APKs
├── config/
│   └── env.yaml              # Environment variables
├── flows/
│   └── home/
│       ├── 05_weather_widget_location.yaml
│       ├── 06_type_question_ai_response.yaml
│       ├── 08_home_feed_scroll.yaml
│       ├── 11_listen_ai_response.yaml
│       └── 25_settings_logout.yaml
├── helpers/
│   ├── complete_onboarding.yaml
│   ├── dismiss_oppo_popup.yaml
│   ├── open_drawer.yaml
│   └── navigate_to_settings.yaml
└── reports/                  # Generated test reports (gitignored)
```

---

## Troubleshooting

### "No Android device connected"
- Ensure USB Debugging is enabled on device
- Run `adb devices` to verify connection
- Try `adb kill-server && adb start-server`

### OPPO Installation Popup
- The script automatically handles OPPO's app verification popups
- If stuck, manually tap "Continue installation" then "Close"

### Maestro Connection Issues
- Run `./setup_device.sh` to manually install Maestro APKs
- Ensure device screen is unlocked during tests

### Tests Timing Out
- Check device has stable internet connection
- Ensure FarmerChat app is installed and working

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GDRIVE_FOLDER_ID` | (none) | Google Drive folder ID for uploads |
| `RCLONE_REMOTE` | `gdrive` | rclone remote name |
| `APP_ID` | `org.digitalgreen.farmer.chat` | App package name |

---

## Support

For issues or questions, contact the QA team or raise an issue in this repository.
