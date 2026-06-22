#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repo = process.env.WB_REPO || "aduermael/wb";
const binDir = path.resolve(__dirname, "..", "bin");
const binaryPath = path.join(binDir, "wb");
const userAgent = "wb-npm-installer";

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

async function main() {
  fs.mkdirSync(binDir, { recursive: true });

  if (process.env.WB_NATIVE_BINARY) {
    installLocalBinary(process.env.WB_NATIVE_BINARY);
    return;
  }

  const assetName = assetNameForCurrentPlatform();
  const release = releaseSegment(packageVersion());
  const baseUrl = process.env.WB_BINARY_BASE_URL || releaseBaseUrl(repo, release);
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "wb-npm-"));

  try {
    const archivePath = path.join(tmpDir, assetName);
    const checksumPath = `${archivePath}.sha256`;

    await download(`${baseUrl}/${assetName}`, archivePath);
    await download(`${baseUrl}/${assetName}.sha256`, checksumPath);
    verifyChecksum(archivePath, checksumPath);
    extractArchive(archivePath, tmpDir);

    const extractedBinaryPath = path.join(tmpDir, "wb");
    if (!fs.existsSync(extractedBinaryPath)) {
      throw new Error(`release archive did not contain a wb binary`);
    }

    installBinary(extractedBinaryPath);
    console.log(`Installed wb ${release === "latest" ? "latest" : release} for ${process.platform}/${process.arch}`);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

function packageVersion() {
  if (process.env.WB_VERSION) {
    return process.env.WB_VERSION;
  }
  if (process.env.npm_package_version) {
    return process.env.npm_package_version;
  }

  const packageJsonPath = path.resolve(__dirname, "..", "..", "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  return packageJson.version;
}

function releaseSegment(version) {
  const normalized = String(version || "").trim();
  if (!normalized || normalized === "latest" || normalized.startsWith("0.0.0-")) {
    return "latest";
  }
  return normalized.startsWith("v") ? normalized : `v${normalized}`;
}

function releaseBaseUrl(repository, release) {
  if (release === "latest") {
    return `https://github.com/${repository}/releases/latest/download`;
  }
  return `https://github.com/${repository}/releases/download/${release}`;
}

function assetNameForCurrentPlatform() {
  if (process.platform !== "darwin") {
    throw new Error("wb prebuilt releases currently support macOS only.");
  }

  switch (process.arch) {
    case "arm64":
      return "wb-macos-arm64.tar.gz";
    case "x64":
      return "wb-macos-x86_64.tar.gz";
    default:
      throw new Error(`unsupported CPU architecture: ${process.arch}`);
  }
}

function installLocalBinary(sourcePath) {
  const resolvedSourcePath = path.resolve(sourcePath);
  if (!fs.existsSync(resolvedSourcePath)) {
    throw new Error(`WB_NATIVE_BINARY does not exist: ${resolvedSourcePath}`);
  }
  installBinary(resolvedSourcePath);
  console.log(`Installed wb from ${resolvedSourcePath}`);
}

function installBinary(sourcePath) {
  fs.copyFileSync(sourcePath, binaryPath);
  fs.chmodSync(binaryPath, 0o755);
}

function download(url, destinationPath, redirectsRemaining = 5) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, { headers: { "User-Agent": userAgent } }, (response) => {
      const statusCode = response.statusCode || 0;
      if (isRedirect(statusCode) && response.headers.location) {
        response.resume();
        if (redirectsRemaining === 0) {
          reject(new Error(`too many redirects while downloading ${url}`));
          return;
        }
        const redirectedUrl = new URL(response.headers.location, url).toString();
        resolve(download(redirectedUrl, destinationPath, redirectsRemaining - 1));
        return;
      }

      if (statusCode !== 200) {
        response.resume();
        reject(new Error(`failed to download ${url}: HTTP ${statusCode}`));
        return;
      }

      const file = fs.createWriteStream(destinationPath, { mode: 0o600 });
      response.pipe(file);
      file.on("finish", () => {
        file.close(resolve);
      });
      file.on("error", reject);
    });

    request.on("error", reject);
  });
}

function isRedirect(statusCode) {
  return [301, 302, 303, 307, 308].includes(statusCode);
}

function verifyChecksum(archivePath, checksumPath) {
  const checksumText = fs.readFileSync(checksumPath, "utf8").trim();
  const expectedChecksum = checksumText.split(/\s+/)[0]?.toLowerCase();
  if (!expectedChecksum || !/^[a-f0-9]{64}$/.test(expectedChecksum)) {
    throw new Error(`invalid checksum file for ${path.basename(archivePath)}`);
  }

  const actualChecksum = crypto.createHash("sha256")
    .update(fs.readFileSync(archivePath))
    .digest("hex");

  if (actualChecksum !== expectedChecksum) {
    throw new Error(
      `checksum mismatch for ${path.basename(archivePath)}: expected ${expectedChecksum}, got ${actualChecksum}`
    );
  }
}

function extractArchive(archivePath, destinationDir) {
  const result = spawnSync("tar", ["-xzf", archivePath, "-C", destinationDir], {
    encoding: "utf8"
  });

  if (result.error) {
    throw new Error(`failed to run tar: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    throw new Error(`failed to extract ${path.basename(archivePath)}${detail ? `: ${detail}` : ""}`);
  }
}
