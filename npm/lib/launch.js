'use strict';

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

function isExecutable(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

function launch(name) {
  const override = process.env[`${name.toUpperCase()}_BIN`];
  const bundled = path.join(
    __dirname,
    '..',
    'dist',
    `${process.platform}-${process.arch}`,
    name
  );

  const bin = [override, bundled].filter(Boolean).find(isExecutable);

  if (!bin) {
    console.error(
      `${name}: no prebuilt binary for ${process.platform}-${process.arch}.`
    );
    console.error(
      'nimtui ships binaries for macOS and Linux (arm64 + x64). On other'
    );
    console.error(
      `platforms, build from source with nim and point ${name.toUpperCase()}_BIN at the binary.`
    );
    process.exit(1);
  }

  const result = spawnSync(bin, process.argv.slice(2), { stdio: 'inherit' });
  if (result.error) {
    console.error(`${name}: ${result.error.message}`);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
}

module.exports = launch;
