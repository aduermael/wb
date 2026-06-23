/// Runs the WebPageCLI test cases without relying on XCTest or Swift Testing
/// modules, which are not present in every Swift toolchain installation.
let cliParserTests = CLIParserTests()
TestHarness.run("CLIParserTests.testEmptyArgumentsShowRootHelp") {
	try cliParserTests.testEmptyArgumentsShowRootHelp()
}
TestHarness.run("CLIParserTests.testCreateListAndRemoveCommands") {
	try cliParserTests.testCreateListAndRemoveCommands()
}
TestHarness.run("CLIParserTests.testShowHideAndResizeCommands") {
	try cliParserTests.testShowHideAndResizeCommands()
}
TestHarness.run("CLIParserTests.testPositionalOpenNormalizesBrowserIdShape") {
	try cliParserTests.testPositionalOpenNormalizesBrowserIdShape()
}
TestHarness.run("CLIParserTests.testPageOptionsCanAppearBeforeBrowserId") {
	try cliParserTests.testPageOptionsCanAppearBeforeBrowserId()
}
TestHarness.run("CLIParserTests.testClickFillSubmitAndEvalCommands") {
	try cliParserTests.testClickFillSubmitAndEvalCommands()
}
TestHarness.run("CLIParserTests.testCoordinateCommandsRejectInvalidNumbers") {
	try cliParserTests.testCoordinateCommandsRejectInvalidNumbers()
}
TestHarness.run("CLIParserTests.testScreenshotAndDaemonCommands") {
	try cliParserTests.testScreenshotAndDaemonCommands()
}

let coordinateAndDaemonTests = CoordinateAndDaemonTests()
TestHarness.run("CoordinateAndDaemonTests.testCoordinateActionBuildsClickPressDragAndRelease") {
	try coordinateAndDaemonTests.testCoordinateActionBuildsClickPressDragAndRelease()
}
TestHarness.run("CoordinateAndDaemonTests.testCoordinateActionBuildsScrollWithDeltas") {
	try coordinateAndDaemonTests.testCoordinateActionBuildsScrollWithDeltas()
}
TestHarness.run("CoordinateAndDaemonTests.testCoordinateActionRejectsMissingAndUnknownActions") {
	coordinateAndDaemonTests.testCoordinateActionRejectsMissingAndUnknownActions()
}
TestHarness.run("CoordinateAndDaemonTests.testDaemonActivityTracksInFlightRequestsAndTimeouts") {
	coordinateAndDaemonTests.testDaemonActivityTracksInFlightRequestsAndTimeouts()
}

let pageFieldAndProtocolTests = PageFieldAndProtocolTests()
TestHarness.run("PageFieldAndProtocolTests.testPageFieldListParsingTrimsAndDeduplicatesNames") {
	try pageFieldAndProtocolTests.testPageFieldListParsingTrimsAndDeduplicatesNames()
}
TestHarness.run("PageFieldAndProtocolTests.testWireRequestBuilderAndRequiredValues") {
	try pageFieldAndProtocolTests.testWireRequestBuilderAndRequiredValues()
}
TestHarness.run("PageFieldAndProtocolTests.testWireRequestBrowserRemovalTarget") {
	try pageFieldAndProtocolTests.testWireRequestBrowserRemovalTarget()
}
TestHarness.run("PageFieldAndProtocolTests.testResourceTimeoutValidationAndWaitSemantics") {
	try pageFieldAndProtocolTests.testResourceTimeoutValidationAndWaitSemantics()
}
TestHarness.run("PageFieldAndProtocolTests.testResourceLoadingValidationRejectsUnsupportedCommands") {
	try pageFieldAndProtocolTests.testResourceLoadingValidationRejectsUnsupportedCommands()
}
TestHarness.run("PageFieldAndProtocolTests.testTypingDelayValidation") {
	try pageFieldAndProtocolTests.testTypingDelayValidation()
}
TestHarness.run("PageFieldAndProtocolTests.testWindowSizeValidation") {
	try pageFieldAndProtocolTests.testWindowSizeValidation()
}
TestHarness.run("PageFieldAndProtocolTests.testPageLoadStatusTracksPageResourceAndQuietStates") {
	try pageFieldAndProtocolTests.testPageLoadStatusTracksPageResourceAndQuietStates()
}
TestHarness.run("PageFieldAndProtocolTests.testPageLoadStatusInteractionSettlingUsesShortQuietCriteria") {
	try pageFieldAndProtocolTests.testPageLoadStatusInteractionSettlingUsesShortQuietCriteria()
}
TestHarness.run("PageFieldAndProtocolTests.testWireResponsesPreserveProtocolVersionAndBuilderFields") {
	try pageFieldAndProtocolTests.testWireResponsesPreserveProtocolVersionAndBuilderFields()
}
TestHarness.run("PageFieldAndProtocolTests.testWireCodecRoundTripsResponsesAndErrors") {
	try pageFieldAndProtocolTests.testWireCodecRoundTripsResponsesAndErrors()
}
TestHarness.run("PageFieldAndProtocolTests.testPageSnapshotDecodesCurrentResourcesAndLegacyImagePayloads") {
	try pageFieldAndProtocolTests.testPageSnapshotDecodesCurrentResourcesAndLegacyImagePayloads()
}

let renderingAndUtilityTests = RenderingAndUtilityTests()
TestHarness.run("RenderingAndUtilityTests.testOptionalAndStringHelpers") {
	try renderingAndUtilityTests.testOptionalAndStringHelpers()
}
TestHarness.run("RenderingAndUtilityTests.testISO8601HelpersRoundTripStableDates") {
	try renderingAndUtilityTests.testISO8601HelpersRoundTripStableDates()
}
TestHarness.run("RenderingAndUtilityTests.testPrintableHandlesCommonJavaScriptBridgeValues") {
	try renderingAndUtilityTests.testPrintableHandlesCommonJavaScriptBridgeValues()
}
TestHarness.run("RenderingAndUtilityTests.testCompactJSONStringSortsKeysAndPrunesDefaults") {
	try renderingAndUtilityTests.testCompactJSONStringSortsKeysAndPrunesDefaults()
}
TestHarness.run("RenderingAndUtilityTests.testScreenshotRenderSettlingMillisecondsRoundUp") {
	try renderingAndUtilityTests.testScreenshotRenderSettlingMillisecondsRoundUp()
}
TestHarness.run("RenderingAndUtilityTests.testScreenshotRenderSettlingTotalWaitBudget") {
	try renderingAndUtilityTests.testScreenshotRenderSettlingTotalWaitBudget()
}
TestHarness.run("RenderingAndUtilityTests.testRenderedOutputForSummaryPageAndActions") {
	try renderingAndUtilityTests.testRenderedOutputForSummaryPageAndActions()
}
TestHarness.run("RenderingAndUtilityTests.testRenderedOutputForSimpleModesAndErrors") {
	try renderingAndUtilityTests.testRenderedOutputForSimpleModesAndErrors()
}

let updaterTests = UpdaterTests()
TestHarness.run("UpdaterTests.testUpdateAndVersionCommandsParseAsLocalCommands") {
	try updaterTests.testUpdateAndVersionCommandsParseAsLocalCommands()
}
TestHarness.run("UpdaterTests.testUpdateCheckStateThrottlesForTwelveHours") {
	updaterTests.testUpdateCheckStateThrottlesForTwelveHours()
}
TestHarness.run("UpdaterTests.testUpdateCheckResultNormalizesTagsAndSkipsDevelopmentBuilds") {
	updaterTests.testUpdateCheckResultNormalizesTagsAndSkipsDevelopmentBuilds()
}
TestHarness.run("UpdaterTests.testAutomaticUpdateChecksCanBeDisabledWithEnvironment") {
	updaterTests.testAutomaticUpdateChecksCanBeDisabledWithEnvironment()
}
TestHarness.run("UpdaterTests.testGitHubReleaseDecodesAssets") {
	try updaterTests.testGitHubReleaseDecodesAssets()
}
TestHarness.run("UpdaterTests.testInstallationDetectorIdentifiesHomebrewExecutable") {
	try updaterTests.testInstallationDetectorIdentifiesHomebrewExecutable()
}
TestHarness.run("UpdaterTests.testInstallationDetectorIdentifiesNPMExecutable") {
	try updaterTests.testInstallationDetectorIdentifiesNPMExecutable()
}
TestHarness.run("UpdaterTests.testInstallationDetectorAllowsNPMOverride") {
	try updaterTests.testInstallationDetectorAllowsNPMOverride()
}
TestHarness.run("UpdaterTests.testHomebrewUpgradeDisablesAskMode") {
	updaterTests.testHomebrewUpgradeDisablesAskMode()
}
TestHarness.run("UpdaterTests.testStreamingCommandsCanAutoConfirmPrompts") {
	try updaterTests.testStreamingCommandsCanAutoConfirmPrompts()
}
TestHarness.run("UpdaterTests.testStreamingCommandsCanOverrideEnvironment") {
	try updaterTests.testStreamingCommandsCanOverrideEnvironment()
}

let skillInstallerTests = SkillInstallerTests()
TestHarness.run("SkillInstallerTests.testInstallSkillCommandParsesTargetsAndMode") {
	try skillInstallerTests.testInstallSkillCommandParsesTargetsAndMode()
}
TestHarness.run("SkillInstallerTests.testSkillInstallerInstallsAndDetectsUnchangedTarget") {
	try skillInstallerTests.testSkillInstallerInstallsAndDetectsUnchangedTarget()
}
TestHarness.run("SkillInstallerTests.testSkillInstallerAutoUpdateOnlyTouchesExistingTargets") {
	try skillInstallerTests.testSkillInstallerAutoUpdateOnlyTouchesExistingTargets()
}
TestHarness.run("SkillInstallerTests.testSkillInstallerTreatsMissingExecutableBitAsOutdated") {
	try skillInstallerTests.testSkillInstallerTreatsMissingExecutableBitAsOutdated()
}
TestHarness.run("SkillInstallerTests.testEmbeddedSkillPayloadMatchesCheckedInFiles") {
	try skillInstallerTests.testEmbeddedSkillPayloadMatchesCheckedInFiles()
}
TestHarness.run("SkillInstallerTests.testSkillAutoUpdaterLaunchDecisionSkipsNonProjectCommands") {
	try skillInstallerTests.testSkillAutoUpdaterLaunchDecisionSkipsNonProjectCommands()
}
TestHarness.run("SkillInstallerTests.testProjectDirectoryUsesNearestGitRoot") {
	try skillInstallerTests.testProjectDirectoryUsesNearestGitRoot()
}

let sessionStoreTests = SessionStoreTests()
TestHarness.run("SessionStoreTests.testIdleTimeoutParsing") {
	sessionStoreTests.testIdleTimeoutParsing()
}
TestHarness.run("SessionStoreTests.testEnvironmentLoadOrCreatePersistsStableMetadata") {
	try sessionStoreTests.testEnvironmentLoadOrCreatePersistsStableMetadata()
}
TestHarness.run("SessionStoreTests.testSessionStoreSaveLoadListAndDelete") {
	try sessionStoreTests.testSessionStoreSaveLoadListAndDelete()
}
TestHarness.run("SessionStoreTests.testSessionStoreRejectsBadBrowserIdsAndMismatchedDumps") {
	try sessionStoreTests.testSessionStoreRejectsBadBrowserIdsAndMismatchedDumps()
}
TestHarness.run("SessionStoreTests.testBrowserDumpSummaryUsesSnapshotFallbacksAndDates") {
	sessionStoreTests.testBrowserDumpSummaryUsesSnapshotFallbacksAndDates()
}

TestHarness.finish()
