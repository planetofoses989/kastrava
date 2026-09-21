// Custom Windows signer for electron-builder (wired via build.win.signtoolOptions.sign).
//
// electron-builder's bundled winCodeSign signtool cannot sign .appx/.msix
// packages ("SignTool Error: A required function is not present"), so for
// AppX/MSIX targets we sign with the Windows SDK signtool that ships on the
// GitHub Actions windows runner instead. NSIS/portable EXEs stay unsigned (no
// certificate is configured for them, and this hook skips when cscInfo is
// null), keeping their SmartScreen behavior exactly as before.
//
// The Microsoft Store re-signs submitted packages at ingestion, so the
// self-signed certificate used here is a well-formedness requirement, not a
// trust anchor.

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const SDK_BIN = "C:\\Program Files (x86)\\Windows Kits\\10\\bin";

function findLatestSdkVersionDir() {
  if (!fs.existsSync(SDK_BIN)) return null;
  const versions = fs
    .readdirSync(SDK_BIN)
    .filter((name) => /^\d+\.\d+\.\d+\.\d+$/.test(name))
    .sort((a, b) => {
      const pa = a.split(".").map(Number);
      const pb = b.split(".").map(Number);
      for (let i = 0; i < 4; i++) {
        if (pa[i] !== pb[i]) return pb[i] - pa[i];
      }
      return 0;
    });
  return versions.length > 0 ? path.join(SDK_BIN, versions[0]) : null;
}

function findSdkSigntool() {
  const candidates = [];
  const latest = findLatestSdkVersionDir();
  if (latest) {
    candidates.push(path.join(latest, "x64", "signtool.exe"));
    candidates.push(path.join(latest, "x86", "signtool.exe"));
  }
  candidates.push(
    "C:\\Program Files (x86)\\Windows Kits\\10\\App Certification Kit\\signtool.exe"
  );
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(
    "Windows SDK signtool not found; looked in: " + candidates.join(", ")
  );
}

function runSigntool(signtool, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(signtool, args, { stdio: "inherit" });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`signtool exited with code ${code}`));
    });
  });
}

async function sign(configuration) {
  const { path: file, hash, cscInfo } = configuration;

  if (!cscInfo) {
    // No certificate configured (e.g. the unsigned NSIS/portable build) —
    // skip, matching electron-builder's default behavior for unsigned builds.
    return undefined;
  }
  if (!("file" in cscInfo) || !cscInfo.file) {
    throw new Error(
      "win-sign: certificate is not a local PFX; this hook only supports file-based signing."
    );
  }

  const signtool = findSdkSigntool();
  const args = ["sign"];
  args.push("/f", cscInfo.file);
  if (cscInfo.password) args.push("/p", cscInfo.password);
  args.push("/fd", hash === "sha1" ? "sha1" : "sha256");
  if (process.env.ELECTRON_BUILDER_OFFLINE !== "true") {
    args.push("/tr", "http://timestamp.digicert.com", "/td", "sha256");
  }
  if (configuration.name) args.push("/d", configuration.name);
  if (configuration.site) args.push("/du", configuration.site);
  args.push(file);

  await runSigntool(signtool, args);
}

module.exports = { sign };