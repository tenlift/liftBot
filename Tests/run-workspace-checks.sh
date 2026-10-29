#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/sidebar-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="$check_dir/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$check_dir/swift-cache"
sources='侧伴/侧伴'
swift build --build-system native --disable-sandbox --cache-path "$check_dir/cache" --config-path "$check_dir/config" --security-path "$check_dir/security" --package-path Packages/SidebarCore --scratch-path "$check_dir/package"
bin_path=$(swift build --build-system native --disable-sandbox --cache-path "$check_dir/cache" --config-path "$check_dir/config" --security-path "$check_dir/security" --package-path Packages/SidebarCore --scratch-path "$check_dir/package" --show-bin-path)
xcrun swiftc -parse-as-library -I "$bin_path/Modules" "$bin_path"/SidebarCore.build/*.swift.o \
    "$sources/Platform/Localization/L10n.swift" \
    "$sources/Features/Focus/PomodoroTimer.swift" \
    "$sources/Platform/Storage/StorageLocations.swift" \
    "$sources/Features/Calendar/HolidayCalendar.swift" \
    "$sources/Platform/Audio/RecordingStore.swift" \
    "$sources/Platform/Audio/SpeechTranscriber.swift" \
    "$sources/Platform/Notifications/NotificationService.swift" \
    Tests/FakeNotificationBackend.swift \
    "$sources/Platform/Shortcuts/ShortcutManager.swift" \
    "$sources/Platform/Shortcuts/CarbonHotKeyBackend.swift" \
    Tests/ShortcutChecks.swift \
    Tests/NoteDestinationChecks.swift \
    "$sources/Platform/Storage/FileDropSupport.swift" \
    "$sources/Workspace/WorkspaceStore.swift" \
    "$sources/Workspace/WorkspaceStore+Files.swift" \
    "$sources/Workspace/WorkspaceStore+Export.swift" \
    Tests/WorkspaceChecks.swift -o "$check_dir/checks"
"$check_dir/checks"

# Optional native integration check: requires a macOS window server and a free test combination.
if [[ "${RUN_NATIVE_SHORTCUT_CHECKS:-0}" == "1" ]]; then
    xcrun swiftc -parse-as-library -I "$bin_path/Modules" "$bin_path"/SidebarCore.build/*.swift.o \
        "$sources/Platform/Localization/L10n.swift" \
        "$sources/Platform/Shortcuts/ShortcutManager.swift" \
        "$sources/Platform/Shortcuts/CarbonHotKeyBackend.swift" \
        Tests/NativeShortcutChecks.swift -o "$check_dir/native-shortcuts"
    "$check_dir/native-shortcuts"
fi
