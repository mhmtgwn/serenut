const assert = require('node:assert/strict');
const fs = require('node:fs');

const workflow = fs.readFileSync('.github/workflows/deploy.yml', 'utf8');
const manualWorkflow = fs.readFileSync(
  '.github/workflows/publish-client-artifacts.yml',
  'utf8',
);
const deployScript = fs.readFileSync(
  'server/scripts/deploy_production_ci.sh',
  'utf8',
);

assert.match(
  workflow,
  /_incoming\/\$\{\{ steps\.release-version\.outputs\.value \}\}/,
  'automatic releases must upload into a version-specific incoming directory',
);
assert.match(
  workflow,
  /git reset --hard '\$\{\{ github\.sha \}\}'/,
  'automatic releases must deploy the commit that produced the artifacts',
);
assert.match(
  manualWorkflow,
  /steps\.source-run\.outputs\.head_sha/,
  'manual recovery must deploy the successful source run commit',
);
assert.match(
  deployScript,
  /flock -w 1200/,
  'VPS release publishing must be serialized with an OS file lock',
);
assert.match(
  deployScript,
  /_incoming\/\$VERSION/,
  'the publisher must read only the requested version incoming directory',
);
assert.match(
  deployScript,
  /SOURCE_VERSION.*VERSION/s,
  'the checked-out source version must match the artifact version',
);

console.log('Release pipeline isolation contract: PASS');
