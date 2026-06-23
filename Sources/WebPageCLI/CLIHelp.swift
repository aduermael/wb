/// Contains all command help copy for the browser CLI so user-facing usage text
/// stays centralized while parsing and rendering logic remain focused on command
/// behavior.
import Foundation

func printHelp(_ topic: HelpTopic) {
	switch topic {
	case .root:
		print(
			"""
			wb is a browser CLI for headless, persistent, and scriptable web sessions.

			Usage:
			  wb [<id>] <url> [--wait-resources] [--resource-timeout <seconds>]
			  wb env
			  wb install-skill [--codex] [--claude] [--grok] [--all]
			  wb update
			  wb version
			  wb create
			  wb list [--quiet|-q]
			  wb remove <id> [<id> ...]
			  wb remove --all
			  wb show <id>
			  wb hide <id>
			  wb resize <id> [<width> <height>]
			  wb screenshot <id> <destination.png|destination.jpg> [--resource-timeout <seconds>]
			    [--capture-delay <seconds>]
			  wb wait-resources <id> [--resource-timeout <seconds>]

			  wb page <id> [--fields <list>] [--selectors|--action-details]
			    [--resource-timeout <seconds>]
			  wb click <id> <action>
			  wb click <id> <x> <y>
			  wb press <id> <x> <y>
			  wb drag <id> <x> <y>
			  wb release <id> <x> <y>
			  wb scroll <id> <x> <y> <deltaX> <deltaY>
			  wb type <id> <action> <text> [--backend js|native] [--rhythm flat|natural]
			    [--speed <factor>] [--delay-min <seconds>] [--delay-max <seconds>]
			  wb fill <id> <action> <text>
			  wb submit <id> <action>
			  wb eval <id> [--body] <javascript>

			  wb daemon <start|status|log|stop>

			Options:
			  -h, --help            Show help.
			  -V, --version         Show the wb version.

			Notes:
			  - Browsers persist between commands; use wb list to see saved IDs.
			  - JSON output is compact; fields with default values are omitted.
			  - URL opens return after page HTML is ready. Use wait-resources after
			    navigation when scripts, styles, images, and fetches matter.
			  - --resource-timeout accepts 0-\(Int(ResourceLoading.maxTimeout)) seconds.
			  - Run 'wb <command> --help' for command details.
			""")

	case .environment:
		print(
			"""
			Usage:
			  wb env

			Prints public metadata for the current wb environment.

			By default, wb uses .wb next to the nearest parent .git directory.
			Outside a git checkout, it uses .wb under the current directory.
			Set WB_DIR to override the environment directory.
			""")

	case .installSkill:
		print(
			"""
			Usage:
			  wb install-skill [--codex] [--claude] [--grok] [--all]
			  wb install-skill --auto-update-existing

			Installs the embedded wb agent skill and its bundled install.sh support script.

			Options:
			  --codex                  Install .agents/skills/wb.
			  --claude                 Install .claude/skills/wb.
			  --grok                   Install .grok/skills/wb.
			  --all                    Install all default agent targets.
			  --target <name|path>     Install one named target or custom skill directory.
			  --name <name>            Use a skill folder name other than wb.
			  --auto-update-existing   Update only existing wb skill folders; create nothing.

			Notes:
			  - Without target flags, installs Codex, Claude, and Grok skill folders.
			  - Normal wb commands silently refresh existing project skill folders.
			  - Automatic refreshes use --auto-update-existing, so missing targets are not created.
			  - Set WB_SKILL_AUTO_UPDATE=off to disable automatic refreshes.
			""")

	case .update:
		print(
			"""
			Usage:
			  wb update

			Updates wb to the latest GitHub release.

			When wb is installed with Homebrew, this runs brew update and brew upgrade wb.
			When wb is installed with npm, this runs npm install -g @aduermael_/wb@latest.
			Standalone release binaries replace their current executable in place.
			""")

	case .version:
		print(
			"""
			Usage:
			  wb version

			Prints the wb version.
			""")

	case .create:
		print(
			"""
			Usage:
			  wb create

			Creates an empty browser and prints its ID.

			If you already know the URL, use wb <url> instead. It creates a
			new browser, loads the page, and returns the browser ID in the JSON
			summary, so wb create followed by wb <id> <url> is unnecessary.
			""")

	case .list:
		print(
			"""
			Usage:
			  wb list [--quiet|-q]

			Lists active and saved browsers as compact JSON.

			Options:
			  -q, --quiet           Print only browser IDs, one per line.
			""")

	case .remove:
		print(
			"""
			Usage:
			  wb remove <id> [<id> ...]
			  wb remove --all

			Removes active browsers and deletes any saved sessions for those IDs.

			Options:
			  --all                 Remove every active and saved browser.
			""")

	case .show:
		print(
			"""
			Usage:
			  wb show <id>

			Shows a lightweight browser window for the browser.
			""")

	case .hide:
		print(
			"""
			Usage:
			  wb hide <id>

			Hides the browser window without closing the browser.
			""")

	case .resize:
		print(
			"""
			Usage:
			  wb resize <id> [<width> <height>]

			Resizes the browser preview window. Without dimensions, resets the
			window to \(BrowserWindowSizing.defaultWidth)x\(BrowserWindowSizing.defaultHeight).

			Dimensions must be at least \(BrowserWindowSizing.minimumWidth)x\(BrowserWindowSizing.minimumHeight).
			""")

	case .screenshot:
		print(
			"""
			Usage:
			  wb screenshot <id> <destination.png|destination.jpg> [--resource-timeout <seconds>]
			    [--capture-delay <seconds>]

			Waits for resources, pauses briefly for visual settling, captures the current browser viewport,
			and writes it to the destination path.
			The image format is selected from the destination extension.

			Options:
			  --resource-timeout <seconds>    Resource wait timeout; default \(Int(ResourceLoading.defaultTimeout)) seconds,
			                                  max \(Int(ResourceLoading.maxTimeout)) seconds.
			  --capture-delay <seconds>       Delay after resource wait before capture; default
			                                  \(ScreenshotCapture.defaultDelay) seconds, max
			                                  \(Int(ScreenshotCapture.maxDelay)) seconds. Use 0 to disable.
			""")

	case .waitResources:
		print(
			"""
			Usage:
			  wb wait-resources <id> [--resource-timeout <seconds>]

			Waits for the current page's resources to become quiet, then prints a compact
			page summary. Timeout is not a command failure; inspect resourcesLoading in the
			summary to see whether the page settled.

			Options:
			  --resource-timeout <seconds>    Resource wait timeout; default
			                                  \(Int(ResourceLoading.waitCommandDefaultTimeout)) seconds,
			                                  max \(Int(ResourceLoading.maxTimeout)) seconds.
			""")

	case .page:
		print(
			"""
			Usage:
			  wb page <id> [--fields <list>] [--selectors|--action-details]
			    [--resource-timeout <seconds>]

			Prints visible page text, page metadata, and actionable elements.

			Options:
			  --fields <list>       Comma-separated fields: \(PageField.validList)
			  --selectors           Include action CSS selectors.
			  --action-details      Include action id, tag, type, and selector.
			  --resource-timeout <seconds>
			                         Wait for resources before printing page JSON.

			Notes:
			  - Without --resource-timeout, page returns immediately.
			  - Default actions include index, kind, text, href, and disabled state.
			  - Resource entries include index, type, and URL. The resources list is capped
			    at 250 entries; resourceCount reports the total discovered resources.
			  - Use action numbers by default; use --action-details to get action IDs.
			""")

	case .click:
		print(
			"""
			Usage:
			  wb click <id> <action>
			  wb click <id> <x> <y>

			Clicks an action from the latest page output.
			<action> may be a 1-based number or an action ID.

			With x and y coordinates, clicks the viewport at that point.
			Coordinate clicks do not open a window; run wb show to observe the page.
			""")

	case .press:
		print(
			"""
			Usage:
			  wb press <id> <x> <y>

			Sends a page mouse-down event at the viewport coordinate.
			Coordinates use a top-left origin.
			""")

	case .drag:
		print(
			"""
			Usage:
			  wb drag <id> <x> <y>

			Sends a page mouse-drag event to the viewport coordinate.
			Use after wb press and before wb release.
			""")

	case .release:
		print(
			"""
			Usage:
			  wb release <id> <x> <y>

			Sends a page mouse-up event at the viewport coordinate.
			Coordinates use a top-left origin.
			""")

	case .scroll:
		print(
			"""
			Usage:
			  wb scroll <id> <x> <y> <deltaX> <deltaY>

			Scrolls at the viewport coordinate without opening a window.
			Coordinates use a top-left origin; deltas use CSS pixel units.
			""")

	case .fill:
		print(
			"""
			Usage:
			  wb fill <id> <action> <text>

			Sets the value of an input, textarea, select, or contenteditable action.
			<action> may be a 1-based number or an action ID.
			""")

	case .type:
		print(
			"""
			Usage:
			  wb type <id> <action> <text> [--backend js|native] [--rhythm flat|natural]
			    [--speed <factor>] [--delay-min <seconds>] [--delay-max <seconds>]

			Focuses a text input, textarea, or contenteditable action, clears existing content,
			then enters text with key/input/change events and short randomized key delays.
			<action> may be a 1-based number or an action ID.

			Options:
			  --backend <js|native>    Typing backend; native is default and sends AppKit
			                           key events to the browser's persistent WebView.
			                           Use js only as a fallback.
			  --rhythm <flat|natural>  Typing rhythm; natural is default and adds short
			                           word and punctuation pauses. Use flat only as a
			                           fallback.
			  --speed <factor>         Typing speed multiplier; default
			                           \(TypingSpeed.defaultFactor). Use 1.0 for the previous speed.
			  --delay-min <seconds>    Minimum randomized delay before each key; default
			                           \(TypingDelay.defaultMin) seconds.
			  --delay-max <seconds>    Maximum randomized delay before each key; default
			                           \(TypingDelay.defaultMax) seconds, max
			                           \(Int(TypingDelay.maxDelay)) seconds.
			""")

	case .submit:
		print(
			"""
			Usage:
			  wb submit <id> <action>

			Submits the nearest form for an action, or clicks the action if no form exists.
			<action> may be a 1-based number or an action ID.
			""")

	case .eval:
		print(
			"""
			Usage:
			  wb eval <id> [--body] <javascript>

			Evaluates JavaScript in the browser and prints the result.

			Options:
			  --body                Treat the script as a WebPage.callJavaScript body.
			""")

	case .daemon:
		print(
			"""
			Usage:
			  wb daemon start [--idle-timeout <seconds|off>]
			  wb daemon status
			  wb daemon log
			  wb daemon stop

			Controls the local browser daemon.
			""")

	case .daemonStart:
		print(
			"""
			Usage:
			  wb daemon start [--idle-timeout <seconds|off>]

			Starts the daemon if it is not running.

			Options:
			  --idle-timeout <seconds|off>    Override idle shutdown for this daemon.
			""")

	case .daemonStatus:
		print(
			"""
			Usage:
			  wb daemon status

			Prints 'running' or 'not running'.
			""")

	case .daemonLog:
		print(
			"""
			Usage:
			  wb daemon log

			Prints the daemon log file path.
			""")

	case .daemonStop:
		print(
			"""
			Usage:
			  wb daemon stop

			Saves active browsers and stops the daemon.
			""")
	}
}
