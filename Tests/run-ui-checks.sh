#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
device_id="${1:?Usage: ./Tests/run-ui-checks.sh <simulator-uuid>}"
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before running UI checks.' >&2; exit 1; }
check_dir="$(mktemp -d /private/tmp/moneynote-ui-checks.XXXXXX)"
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
previous_appearance="$(xcrun simctl ui "$device_id" appearance)"
restore_appearance() {
  if [[ "$previous_appearance" == light || "$previous_appearance" == dark ]]; then
    xcrun simctl ui "$device_id" appearance "$previous_appearance"
  fi
}
trap restore_appearance EXIT
xcrun simctl ui "$device_id" appearance light
xcrun simctl uninstall "$device_id" com.gaoyiming.MoneyNote.SettingsRegression 2>/dev/null || true
python3 - "$project_dir" "$check_dir" <<'PY'
import json, pathlib, sys
root, output = map(pathlib.Path, sys.argv[1:])
settings = {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.gaoyiming.MoneyNote.SettingsRegression',
    'GENERATE_INFOPLIST_FILE': 'YES',
    'INFOPLIST_FILE': str(root / 'MoneyNote/Info.plist'),
    'INFOPLIST_KEY_CFBundleDisplayName': '轻账记回归验证',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone': 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'SWIFT_DEFAULT_ACTOR_ISOLATION': 'MainActor',
    'SWIFT_APPROACHABLE_CONCURRENCY': 'YES',
    'TARGETED_DEVICE_FAMILY': '1,2',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG',
}
spec = {
    'name': 'MoneyNoteUIRegression',
    'options': {'deploymentTarget': {'iOS': '17.0'}},
    'settings': {'base': {'SWIFT_VERSION': '5.0', 'CODE_SIGNING_ALLOWED': 'NO', 'ONLY_ACTIVE_ARCH': 'YES'}},
    'targets': {
        'MoneyNote': {
            'type': 'application', 'platform': 'iOS',
            'sources': [{'path': str(root / 'MoneyNote'), 'excludes': ['Info.plist', '*.entitlements']}],
            'settings': {'base': settings},
        },
        'SettingsInteractionTests': {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [str(root / 'Tests/UI')],
            'dependencies': [{'target': 'MoneyNote'}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'com.gaoyiming.MoneyNote.SettingsInteractionTests', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'MoneyNote'}},
        },
    },
    'schemes': {'MoneyNoteUIRegression': {
        'build': {'targets': {'MoneyNote': 'all', 'SettingsInteractionTests': ['test']}},
        'test': {'targets': ['SettingsInteractionTests'], 'gatherCoverageData': False},
    }},
}
(output / 'project.json').write_text(json.dumps(spec, indent=2))
PY
xcodegen generate --spec "$check_dir/project.json" --project "$check_dir"
xcodebuild -project "$check_dir/MoneyNoteUIRegression.xcodeproj" \
  -scheme MoneyNoteUIRegression -destination "id=$device_id" \
  -derivedDataPath "$check_dir/DerivedData" -jobs 2 \
  -parallel-testing-enabled NO SWIFT_COMPILATION_MODE=wholemodule \
  -resultBundlePath "$check_dir/results.xcresult" test
echo "UI test results: $check_dir/results.xcresult"
