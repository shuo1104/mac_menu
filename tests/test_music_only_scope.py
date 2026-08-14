import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class MusicOnlyScopeTests(unittest.TestCase):
    def test_non_music_modules_are_not_compiled_into_the_app(self):
        project = (ROOT / "MM.xcodeproj/project.pbxproj").read_text()
        app_sources = project.split(
            "14CEF40E2C5CAED300855D72 /* Sources */ = {", 1
        )[1].split("/* End PBXSourcesBuildPhase section */", 1)[0]

        forbidden_sources = {
            "BatteryActivityManager.swift",
            "BatteryStatusViewModel.swift",
            "BrightnessManager.swift",
            "CalendarManager.swift",
            "CalendarModel.swift",
            "CalendarServiceProviding.swift",
            "DragDetector.swift",
            "InlineHUD.swift",
            "MediaKeyInterceptor.swift",
            "MenuBarCore.swift",
            "MenuBarHidingController.swift",
            "MenuBarNotchView.swift",
            "MenuBarProxyManager.swift",
            "MenuBarSettingsView.swift",
            "OpenNotchHUD.swift",
            "QuickShareService.swift",
            "ShelfView.swift",
            "SystemEventIndicatorModifier.swift",
            "VolumeManager.swift",
            "WebcamManager.swift",
            "WebcamView.swift",
            "XPCHelperClient.swift",
            "WritingView.swift",
            "WritingStore.swift",
        }

        for source in forbidden_sources:
            with self.subTest(source=source):
                self.assertNotIn(source, app_sources)

    def test_writing_feature_is_removed(self):
        self.assertFalse(
            (ROOT / "MM/components/Dashboard/WritingView.swift").exists()
        )
        self.assertFalse(
            (ROOT / "MM/integrations/WritingStore.swift").exists()
        )
        dashboard = (
            ROOT / "MM/components/Dashboard/NotchDashboardView.swift"
        ).read_text()
        self.assertNotIn("case writing", dashboard)
        self.assertNotIn("WritingView", dashboard)

    def test_non_music_permissions_are_removed(self):
        with (ROOT / "MM/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        with (ROOT / "MM/MM.entitlements").open("rb") as file:
            entitlements = plistlib.load(file)

        self.assertNotIn("NSScreenCaptureUsageDescription", info)
        for entitlement in (
            "com.apple.security.app-sandbox",
            "com.apple.security.device.camera",
            "com.apple.security.files.bookmarks.app-scope",
            "com.apple.security.files.bookmarks.document-scope",
            "com.apple.security.personal-information.calendars",
            "com.apple.security.network.server",
            "com.apple.security.files.user-selected.read-write",
        ):
            with self.subTest(entitlement=entitlement):
                self.assertNotIn(entitlement, entitlements)

        self.assertTrue(entitlements["com.apple.security.network.client"])
        self.assertTrue(
            entitlements["com.apple.security.automation.apple-events"]
        )

    def test_settings_only_expose_player_related_sections(self):
        settings = (ROOT / "MM/components/Settings/SettingsView.swift").read_text()

        for label in ("Calendar", "HUDs", "Battery", "Shelf", "Menu Bar", "Writing"):
            with self.subTest(label=label):
                self.assertNotIn(f'Label("{label}"', settings)

        # Accent color recovery path restored after Advanced settings removal.
        self.assertIn("useCustomAccentColor", settings)
        self.assertIn("使用音乐可视化频谱", settings)

    def test_notch_dashboard_has_home_and_usage_with_dynamic_height(self):
        dashboard = (
            ROOT / "MM/components/Dashboard/NotchDashboardView.swift"
        ).read_text()
        sizing = (ROOT / "MM/sizing/matters.swift").read_text()
        app = (ROOT / "MM/MMApp.swift").read_text()
        view_model = (
            ROOT / "MM/models/MMViewModel.swift"
        ).read_text()

        for page in ("home", "usage"):
            with self.subTest(page=page):
                self.assertIn(f"case {page}", dashboard)

        self.assertIn("NotchHomePage", dashboard)
        self.assertIn("OpenUsageView", dashboard)
        self.assertIn("width: 640, height: 190", sizing)
        self.assertIn("topBarHeight", dashboard)
        self.assertIn("onPreferredHeightChange", dashboard)
        self.assertIn("setOpenHeight", dashboard)
        self.assertIn("resizeNotchWindow", app)
        self.assertIn("notchWindowSizeChanged", view_model)

    def test_openusage_collectors_are_embedded_without_loopback_dependency(self):
        client = (
            ROOT / "MM/integrations/OpenUsageClient.swift"
        ).read_text()
        package = ROOT / "Vendor/OpenUsageKit/Package.swift"
        facade = ROOT / "Vendor/OpenUsageKit/Sources/OpenUsage/OpenUsageEmbeddedService.swift"

        self.assertTrue(package.exists())
        self.assertTrue(facade.exists())
        self.assertTrue((ROOT / "Vendor/OpenUsageKit/UPSTREAM.md").exists())
        self.assertIn("import OpenUsageKit", client)
        self.assertIn("EmbeddedOpenUsageService", client)
        self.assertNotIn("127.0.0.1:6736", client)
        # App-local period key, not the vendor's openusage.totalSpend.period
        self.assertIn(
            'static let storageKey = "MM.openusage.tokenPeriod"',
            client,
        )
        self.assertNotIn(
            'static let storageKey = "openusage.totalSpend.period"',
            client,
        )

    def test_usage_reference_layout_is_present(self):
        usage_view = (
            ROOT / "MM/components/Dashboard/OpenUsageView.swift"
        ).read_text()

        for component in (
            "ModelUsageBarChart",
            "ModelUsageBarRow",
            "UsagePeriodPicker",
            "ProviderQuotaCard",
            "UsageSparkline",
        ):
            with self.subTest(component=component):
                self.assertIn(component, usage_view)

        self.assertIn('Image("provider-codex")', usage_view)
        self.assertIn('Image("provider-cursor")', usage_view)
        self.assertNotIn("ModelUsageRanking", usage_view)
        self.assertNotIn("ModelUsageDonut", usage_view)
        self.assertNotIn('Text("模型用量")', usage_view)
        self.assertIn("preferredWindowHeight", usage_view)
        # No string surgery on vendor English display text.
        self.assertNotIn('replacingOccurrences(of: "left"', usage_view)
        self.assertIn("fractionRemaining", usage_view)

        model_chart = usage_view.split(
            "private struct ModelUsageBarChart", 1
        )[1].split("private struct ModelUsageBarRow", 1)[0]
        self.assertIn("ScrollView", model_chart)

    def test_usage_period_switch_has_one_window_sizing_authority(self):
        app = (ROOT / "MM/MMApp.swift").read_text()
        usage_view = (
            ROOT / "MM/components/Dashboard/OpenUsageView.swift"
        ).read_text()

        self.assertIn("hostingView.sizingOptions = []", app)
        self.assertNotIn(".onChange(of: tokenPeriod)", usage_view)
        self.assertIn("maximumVisibleModelCount", usage_view)
        self.assertIn(
            ".onChange(of: maximumVisibleModelCount)",
            usage_view,
        )
        self.assertNotIn(".onChange(of: visibleModelCount)", usage_view)
        self.assertNotIn(".id(tokenPeriod)", usage_view)
        self.assertIn("@AppStorage(UsagePeriod.storageKey)", usage_view)
        self.assertIn("matchedGeometryEffect", usage_view)

    def test_home_usage_marks_live_inside_the_music_player(self):
        dashboard = (
            ROOT / "MM/components/Dashboard/NotchDashboardView.swift"
        ).read_text()
        player = (
            ROOT / "MM/components/Notch/NotchHomeView.swift"
        ).read_text()

        home_page = dashboard.split("struct NotchHomePage", 1)[1]
        self.assertNotIn("HomeUsageStrip()", home_page)
        self.assertIn("HomeUsageStrip()", player)
        self.assertNotIn("struct NotchHomeView", player)

    def test_openusage_settings_are_inside_mm_settings(self):
        settings = (
            ROOT / "MM/components/Settings/SettingsView.swift"
        ).read_text()

        self.assertIn('Label("用量"', settings)
        self.assertIn("OpenUsageSettings", settings)
        self.assertIn("refreshIntervalSeconds", settings)
        self.assertIn("setProviderEnabled", settings)

    def test_clicking_outside_closes_the_open_notch(self):
        monitor = ROOT / "MM/components/Notch/NotchOutsideClickMonitor.swift"
        content = (ROOT / "MM/ContentView.swift").read_text()
        monitor_text = monitor.read_text()

        self.assertTrue(monitor.exists())
        self.assertIn("NSEvent.addGlobalMonitorForEvents", monitor_text)
        self.assertIn("outsideClickMonitor", content)
        # Own windows (Settings, panels) must not count as outside.
        self.assertIn("clickedOwnWindow", monitor_text)
        self.assertNotIn("window is MMSkyLightWindow", monitor_text)

    def test_embedded_package_supports_the_release_xcode_toolchain(self):
        package = (ROOT / "Vendor/OpenUsageKit/Package.swift").read_text()

        self.assertIn("// swift-tools-version: 6.1", package)
        self.assertNotIn("// swift-tools-version: 6.2", package)

    def test_writing_controls_can_request_key_window_focus(self):
        # Key focus still required for Usage detail and settings text fields.
        window = (
            ROOT
            / "MM/components/Notch/MMSkyLightWindow.swift"
        ).read_text()

        self.assertIn("becomesKeyOnlyIfNeeded = true", window)
        self.assertIn("override var canBecomeKey: Bool { true }", window)

    def test_screen_recording_privacy_preference_is_honored(self):
        window = (
            ROOT
            / "MM/components/Notch/MMSkyLightWindow.swift"
        ).read_text()
        constants = (ROOT / "MM/models/Constants.swift").read_text()
        settings = (
            ROOT / "MM/components/Settings/SettingsView.swift"
        ).read_text()

        self.assertIn("Defaults[.hideFromScreenRecording]", window)
        self.assertIn("static let hideFromScreenRecording", constants)
        self.assertIn("录屏时隐藏", settings)

    def test_unavailable_preferred_display_falls_back_to_main_display(self):
        app = (ROOT / "MM/MMApp.swift").read_text()

        self.assertIn(
            "if let preferredUUID = coordinator.preferredScreenUUID,\n"
            "           let preferredScreen = NSScreen.screen(withUUID: preferredUUID)",
            app,
        )

    def test_open_dashboard_taps_do_not_reset_dynamic_height(self):
        content = (ROOT / "MM/ContentView.swift").read_text()
        open_notch = content.split("private func openNotch()", 1)[1].split(
            "private func handleHover", 1
        )[0]

        self.assertIn("guard vm.notchState == .closed else { return }", open_notch)

    def test_adjust_window_position_does_not_force_close_open_notch(self):
        app = (ROOT / "MM/MMApp.swift").read_text()
        adjust = app.split(
            "private func adjustWindowPosition(changeAlpha: Bool = false)", 1
        )[1].split(
            "private func screenConfigurationDidChange", 1
        )[0]

        self.assertIn("if model.notchState == .closed", adjust)
        self.assertIn("if viewModel.notchState == .closed", adjust)
        # Unconditional close() after position() was the regression.
        self.assertNotIn("viewModels[uuid]?.close()\n                }", adjust)

    def test_onboarding_window_is_not_closable_without_finish(self):
        app = (ROOT / "MM/MMApp.swift").read_text()
        onboarding = app.split("private func showMusicSourceOnboarding()", 1)[1]

        self.assertIn("styleMask: [.titled, .fullSizeContentView]", onboarding)
        self.assertNotIn(".closable", onboarding)
        self.assertIn("[weak onboardingWindow]", onboarding)

    def test_window_height_mode_keeps_legacy_raw_values(self):
        enums = (ROOT / "MM/enums/generic.swift").read_text()

        self.assertIn('case matchMenuBar = "Match menubar height"', enums)
        self.assertIn(
            'case matchRealNotchSize = "Match real notch height"', enums
        )
        self.assertIn("migratePersistedValuesIfNeeded", enums)

    def test_media_controller_resolves_unavailable_preference(self):
        constants = (ROOT / "MM/models/Constants.swift").read_text()
        onboarding = (
            ROOT
            / "MM/components/Onboarding/MusicControllerSelectionView.swift"
        ).read_text()
        app = (ROOT / "MM/MMApp.swift").read_text()

        self.assertIn("static func resolved", constants)
        self.assertIn("MediaControllerType.resolved", onboarding)
        self.assertIn("presentOnboardingIfNeeded", app)
        self.assertIn("didFinishDeprecationCheck", app)

    def test_sneak_content_type_is_removed(self):
        coordinator = (
            ROOT / "MM/MMViewCoordinator.swift"
        ).read_text()
        self.assertNotIn("SneakContentType", coordinator)
        self.assertIn("func toggleSneakPeek(\n        status: Bool,", coordinator)
        self.assertIn("func toggleExpandingView(status: Bool)", coordinator)

    def test_keyboard_auto_close_cancels_on_interaction(self):
        content = (ROOT / "MM/ContentView.swift").read_text()
        app = (ROOT / "MM/MMApp.swift").read_text()
        constants = (ROOT / "MM/models/Constants.swift").read_text()

        self.assertIn("cancelNotchAutoClose", constants)
        self.assertIn(".cancelNotchAutoClose", content)
        self.assertIn("cancelNotchAutoClose()", app)

    def test_embedded_usage_seeds_and_detects_local_providers(self):
        service = (
            ROOT
            / "Vendor/OpenUsageKit/Sources/OpenUsage/OpenUsageEmbeddedService.swift"
        ).read_text()

        self.assertIn("seedEmbeddedProvidersIfNeeded", service)
        self.assertIn("hasLocalCredentials()", service)
        self.assertIn("await initialProviderDetectionTask.value", service)

    def test_dead_feature_trees_are_gone(self):
        for path in (
            "MM/components/Shelf",
            "MM/components/Calendar",
            "MM/components/Webcam",
            "MM/XPCHelperClient",
            "MMXPCHelper",
            "MM/observers/MediaKeyInterceptor.swift",
            "MM/managers/VolumeManager.swift",
        ):
            with self.subTest(path=path):
                self.assertFalse((ROOT / path).exists(), path)


if __name__ == "__main__":
    unittest.main()
