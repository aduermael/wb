#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const binaryPath = path.join(__dirname, "wb");

if (!fs.existsSync(binaryPath)) {
  console.error(
    "wb native binary is not installed. Reinstall the package or run `npm rebuild @aduermael_/wb`."
  );
  process.exit(1);
}

const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: "inherit"
});

child.on("error", (error) => {
  console.error(`failed to start wb: ${error.message}`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code === null ? 1 : code);
});
