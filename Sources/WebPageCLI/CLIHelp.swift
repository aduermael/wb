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
			  wb [<id>] <url>
			  wb env
			  wb update
			  wb version
			  wb create
			  wb list
			  wb close <id>
			  wb show <id>
			  wb hide <id>
			  wb screenshot <id> <destination.png|destination.jpg>

			  wb page <id> [--fields <list>] [--selectors|--action-details]
			  wb click <id> <action>
			  wb click <id> <x> <y>
			  wb press <id> <x> <y>
			  wb drag <id> <x> <y>
			  wb release <id> <x> <y>
			  wb scroll <id> <x> <y> <deltaX> <deltaY>
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

	case .update:
		print(
			"""
			Usage:
			  wb update

			Updates wb to the latest GitHub release.

			When wb is installed with Homebrew, this runs brew update and brew upgrade wb.
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
			""")

	case .list:
		print(
			"""
			Usage:
			  wb list

			Lists active and saved browsers as compact JSON.
			""")

	case .close:
		print(
			"""
			Usage:
			  wb close <id>

			Closes an active browser and deletes any saved session for that ID.
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

	case .screenshot:
		print(
			"""
			Usage:
			  wb screenshot <id> <destination.png|destination.jpg>

			Captures the current browser viewport and writes it to the destination path.
			The image format is selected from the destination extension.
			""")

	case .page:
		print(
			"""
			Usage:
			  wb page <id> [--fields <list>] [--selectors|--action-details]

			Prints visible page text, page metadata, and actionable elements.

			Options:
			  --fields <list>       Comma-separated fields: \(PageField.validList)
			  --selectors           Include action CSS selectors.
			  --action-details      Include action id, tag, type, and selector.

			Notes:
			  - Default actions include index, kind, text, href, and disabled state.
			  - Image entries include index and URL.
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
