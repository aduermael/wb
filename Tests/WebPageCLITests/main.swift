/// Runs the WebPageCLI test cases without relying on XCTest or Swift Testing
/// modules, which are not present in every Swift toolchain installation.
let cliParserTests = CLIParserTests()
TestHarness.run("CLIParserTests.testEmptyArgumentsShowRootHelp") {
	try cliParserTests.testEmptyArgumentsShowRootHelp()
}
TestHarness.run("CLIParserTests.testCreateListAndCloseCommands") {
	try cliParserTests.testCreateListAndCloseCommands()
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
TestHarness.run("PageFieldAndProtocolTests.testWireResponsesPreserveProtocolVersionAndBuilderFields") {
	try pageFieldAndProtocolTests.testWireResponsesPreserveProtocolVersionAndBuilderFields()
}
TestHarness.run("PageFieldAndProtocolTests.testWireCodecRoundTripsResponsesAndErrors") {
	try pageFieldAndProtocolTests.testWireCodecRoundTripsResponsesAndErrors()
}
TestHarness.run("PageFieldAndProtocolTests.testPageSnapshotDecodesCurrentAndLegacyImagePayloads") {
	try pageFieldAndProtocolTests.testPageSnapshotDecodesCurrentAndLegacyImagePayloads()
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
TestHarness.run("RenderingAndUtilityTests.testRenderedOutputForSummaryPageAndActions") {
	try renderingAndUtilityTests.testRenderedOutputForSummaryPageAndActions()
}
TestHarness.run("RenderingAndUtilityTests.testRenderedOutputForSimpleModesAndErrors") {
	try renderingAndUtilityTests.testRenderedOutputForSimpleModesAndErrors()
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
