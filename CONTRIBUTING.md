# Contributing

Thanks for helping improve `wb`. This project is a small macOS-first CLI, so changes should keep the command surface predictable, scriptable, and easy for agents to consume.

## Setup

Use a Mac with macOS 26.0 or newer and Xcode 26 or newer with Swift 6.2 SDKs.

Build the project:

```bash
swift build -Xswiftc -warnings-as-errors
```

Build a local signed debug binary at `./wb`:

```bash
./build.sh
```

## Quality Checks

Run formatting before opening a pull request:

```bash
./format.sh
```

Run lint checks:

```bash
./lint.sh
```

Run tests:

```bash
./test.sh
```

The app target depends on AppKit and WebKit, so the full test suite runs on macOS.

## Pull Requests

- Keep changes focused and explain the user-facing behavior they affect.
- Include tests for parser, rendering, session, or browser behavior changes when practical.
- Keep CLI JSON compact and stable. Prefer additive fields over breaking existing output.
- Keep the command surface narrow and agent-oriented. Do not add command aliases, alternate long flags, or alternate value spellings; one canonical spelling plus one-character short flags such as `-h` is enough.
- Update `README.md` or files under `docs/` when commands, install paths, or operational behavior change.

## License

By contributing to this repository, you agree that your contributions are licensed under the MIT License.
