# Maestro Stable Test Suite

A robust and stable Maestro test suite for FarmerChat app, optimized for OPPO/ColorOS devices with Android 16+.

## Project Structure

```
maestro-stable/
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
│   ├── dismiss_oppo_popup.yaml    # OPPO popup handler
│   ├── complete_onboarding.yaml   # App onboarding flow
│   ├── open_drawer.yaml           # Navigation drawer
│   └── navigate_to_settings.yaml  # Settings navigation
├── run_tests.sh              # Test runner script
└── README.md
```

## Test Cases

| File | Description |
|------|-------------|
| `05_weather_widget_location.yaml` | Weather Widget, Grant Location, Verify Feed Cards |
| `06_type_question_ai_response.yaml` | Type Question, Get AI Response, Tap Related Question |
| `08_home_feed_scroll.yaml` | Read Full Advice and Related Questions |
| `11_listen_ai_response.yaml` | Listen to AI Response (TTS Audio Playback) |
| `25_settings_logout.yaml` | Settings Logout |

## Prerequisites

1. **Maestro CLI** installed (`~/.maestro/bin/maestro`)
2. **ADB** configured and device connected
3. **FarmerChat app** installed (debuggable build)

## Usage

### Run All Tests
```bash
chmod +x run_tests.sh
./run_tests.sh
```

### Run with Specific Device
```bash
./run_tests.sh <device_id>
```

### Run Single Test
```bash
maestro test --env APP_ID=org.digitalgreen.farmer.chat \
  --env LANGUAGE="English (Kenya)" \
  --env LANGUAGE_CODE=en \
  --env USER_NAME="Test Farmer" \
  flows/home/05_weather_widget_location.yaml
```

## OPPO Device Handling

This suite includes special handling for OPPO/ColorOS devices:

- **OPPO App Store Popups**: Automatically dismissed via `dismiss_oppo_popup.yaml`
- **pm clear blocked**: Uses `run-as` for app data clearing
- **Maestro APK installation**: Auto-handled with popup dismissal

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_ID` | `org.digitalgreen.farmer.chat` | App package name |
| `LANGUAGE` | `English (Kenya)` | Display language |
| `LANGUAGE_CODE` | `en` | Language code |
| `USER_NAME` | `Test Farmer` | Test user name |
| `WAIT_TIMEOUT` | `10000` | Default wait timeout (ms) |

## Troubleshooting

### OPPO Popup Keeps Appearing
The popup handler runs in background during tests. If it still blocks:
```bash
# Manually dismiss via ADB
adb shell input tap 360 1192  # Continue installation
adb shell input tap 360 1312  # Close button
```

### App Data Not Clearing
Verify app is debuggable:
```bash
adb shell run-as org.digitalgreen.farmer.chat id
```

### Maestro Connection Issues
```bash
adb forward tcp:7001 tcp:7001
```

## License

Internal use only.
