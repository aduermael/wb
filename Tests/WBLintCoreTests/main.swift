/// Runs the WBLintCore test cases without relying on XCTest or Swift Testing
/// modules, which are not present in every Swift toolchain installation.
let filesystemTests = LinterFilesystemTests()
TestHarness.run("LinterFilesystemTests.testRunDiscoversSwiftFilesAndIgnoresGeneratedDirectories") {
	try filesystemTests.testRunDiscoversSwiftFilesAndIgnoresGeneratedDirectories()
}
TestHarness.run("LinterFilesystemTests.testRunReturnsSortedViolationsFromSpecificPaths") {
	try filesystemTests.testRunReturnsSortedViolationsFromSpecificPaths()
}
TestHarness.run("LinterFilesystemTests.testRunReportsMissingPathsAndInvalidUTF8") {
	try filesystemTests.testRunReportsMissingPathsAndInvalidUTF8()
}
TestHarness.run("LinterFilesystemTests.testCommandRunnerReturnsSuccessAndFailureCodes") {
	try filesystemTests.testCommandRunnerReturnsSuccessAndFailureCodes()
}

let ruleTests = LinterRuleTests()
TestHarness.run("LinterRuleTests.testRuleTitlesAndViolationSortingAreStable") {
	ruleTests.testRuleTitlesAndViolationSortingAreStable()
}
TestHarness.run("LinterRuleTests.testFileDocCommentsSupportLineBlockAndPackageHeaderForms") {
	ruleTests.testFileDocCommentsSupportLineBlockAndPackageHeaderForms()
}
TestHarness.run("LinterRuleTests.testFileDocCommentsRejectMissingShortAndLongDocs") {
	ruleTests.testFileDocCommentsRejectMissingShortAndLongDocs()
}
TestHarness.run("LinterRuleTests.testLineRulesDetectEndingsWhitespaceLengthBlanksAndFileLength") {
	ruleTests.testLineRulesDetectEndingsWhitespaceLengthBlanksAndFileLength()
}
TestHarness.run("LinterRuleTests.testLineRulesIgnoreIndentationInsideCommentsAndStrings") {
	ruleTests.testLineRulesIgnoreIndentationInsideCommentsAndStrings()
}
TestHarness.run("LinterRuleTests.testLineRulesDetectMissingFinalNewlineAndSpaceIndentation") {
	ruleTests.testLineRulesDetectMissingFinalNewlineAndSpaceIndentation()
}
TestHarness.run("LinterRuleTests.testImportRulesDetectUnsortedAndDuplicateImportsWithinBlocks") {
	ruleTests.testImportRulesDetectUnsortedAndDuplicateImportsWithinBlocks()
}
TestHarness.run("LinterRuleTests.testDeclarationRulesCountTopLevelParametersOnly") {
	ruleTests.testDeclarationRulesCountTopLevelParametersOnly()
}
TestHarness.run("LinterRuleTests.testSwiftMaskerPreservesNewlinesAndMasksCommentsAndStrings") {
	ruleTests.testSwiftMaskerPreservesNewlinesAndMasksCommentsAndStrings()
}

TestHarness.finish()
