'use strict';

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');

const PORT = 3070;
const RELEASES_ROOT = '/data/releases';
const LOGS_ROOT = '/data/logs';
const TOKEN_FILE = '/run/secrets/maintenance_agent_token';
const MIN_TEMP_AGE_MS = 2 * 60 * 60 * 1000;
const MIN_ARCHIVE_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const ALLOWED_TASKS = new Set([
  'docker_build_cache',
  'dangling_images',
  'stopped_containers',
  'old_releases',
  'temporary_releases',
  'archived_logs',
]);

let cleanupRunning = false;

function bytes(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function safeToken() {
  try { return fs.readFileSync(TOKEN_FILE, 'utf8').trim(); } catch { return ''; }
}

function authorized(req) {
  const expected = safeToken();
  const provided = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!expected || !provided) return false;
  const left = Buffer.from(expected);
  const right = Buffer.from(provided);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function respond(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function dockerRequest(method, endpoint) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      socketPath: '/var/run/docker.sock',
      method,
      path: endpoint,
      headers: { 'content-type': 'application/json' },
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8');
        let payload = {};
        try { payload = raw ? JSON.parse(raw) : {}; } catch { payload = { raw }; }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return reject(new Error(payload.message || `docker_http_${response.statusCode}`));
        }
        resolve(payload);
      });
    });
    request.setTimeout(120_000, () => request.destroy(new Error('docker_timeout')));
    request.on('error', reject);
    request.end();
  });
}

function walkFiles(root) {
  if (!fs.existsSync(root)) return [];
  const output = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) visit(target);
      else if (entry.isFile()) {
        const stat = fs.statSync(target);
        output.push({ path: target, size: stat.size, modifiedAt: stat.mtime.toISOString(), mtimeMs: stat.mtimeMs });
      }
    }
  };
  visit(root);
  return output;
}

function relativeFile(file) {
  const relative = path.relative(RELEASES_ROOT, file.path);
  if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('unsafe_release_path');
  return { path: relative.split(path.sep).join('/'), size: file.size, modifiedAt: file.modifiedAt };
}

function releaseBuildNumber(filePath) {
  const match = path.basename(filePath).match(/\+(\d+)\.(?:apk|exe)$/i);
  return match ? Number(match[1]) : -1;
}

function collectReleaseCandidates(now = Date.now()) {
  const oldStable = [];
  for (const platform of ['android', 'windows']) {
    const stableRoot = path.join(RELEASES_ROOT, platform, 'stable');
    const files = walkFiles(stableRoot)
      .filter((file) => /\.(?:apk|exe)$/i.test(file.path))
      .sort((a, b) => releaseBuildNumber(b.path) - releaseBuildNumber(a.path));
    oldStable.push(...files.slice(2));
  }

  const temporary = ['incoming', '_incoming']
    .flatMap((folder) => walkFiles(path.join(RELEASES_ROOT, folder)))
    .filter((file) => /\.(?:apk|exe)$/i.test(file.path) && now - file.mtimeMs >= MIN_TEMP_AGE_MS);

  return {
    oldStable: oldStable.map(relativeFile),
    temporary: temporary.map(relativeFile),
  };
}

function collectArchivedLogs(now = Date.now()) {
  return walkFiles(LOGS_ROOT)
    .filter((file) => /(?:\.log\.\d+|\.log[-.].+|\.gz)$/i.test(file.path) && now - file.mtimeMs >= MIN_ARCHIVE_AGE_MS)
    .map((file) => {
      const relative = path.relative(LOGS_ROOT, file.path);
      if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('unsafe_log_path');
      return { path: relative.split(path.sep).join('/'), size: file.size, modifiedAt: file.modifiedAt };
    });
}

function sumFiles(files) {
  return files.reduce((total, file) => total + bytes(file.size), 0);
}

async function buildPreview() {
  const [docker, releases, archivedLogs] = await Promise.all([
    dockerRequest('GET', '/system/df'),
    Promise.resolve(collectReleaseCandidates()),
    Promise.resolve(collectArchivedLogs()),
  ]);
  const stat = fs.statfsSync(RELEASES_ROOT);
  const diskTotal = bytes(stat.blocks) * bytes(stat.bsize);
  const diskFree = bytes(stat.bavail) * bytes(stat.bsize);
  const buildCache = Array.isArray(docker.BuildCache) ? docker.BuildCache : [];
  const images = Array.isArray(docker.Images) ? docker.Images : [];
  const containers = Array.isArray(docker.Containers) ? docker.Containers : [];
  const buildCacheBytes = buildCache.filter((item) => !item.InUse).reduce((sum, item) => sum + bytes(item.Size), 0);
  const isDanglingImage = (item) => !Array.isArray(item.RepoTags)
    || item.RepoTags.length === 0
    || item.RepoTags.every((tag) => String(tag).startsWith('<none>:'));
  const danglingImageBytes = images
    .filter(isDanglingImage)
    .reduce((sum, item) => sum + Math.max(0, bytes(item.Size) - bytes(item.SharedSize)), 0);

  return {
    generatedAt: new Date().toISOString(),
    running: cleanupRunning,
    releasePublishInProgress: isReleasePublishInProgress(),
    disk: {
      totalBytes: diskTotal,
      freeBytes: diskFree,
      usedBytes: Math.max(0, diskTotal - diskFree),
      usedPercent: diskTotal ? Number((((diskTotal - diskFree) / diskTotal) * 100).toFixed(1)) : 0,
    },
    protection: {
      databaseVolumes: true,
      accountsAndBusinessData: true,
      activeApplicationLogs: true,
      latestReleaseCountPerPlatform: 2,
    },
    tasks: {
      docker_build_cache: { candidateBytes: buildCacheBytes, candidateCount: buildCache.filter((item) => !item.InUse).length },
      dangling_images: { candidateBytes: danglingImageBytes, candidateCount: images.filter(isDanglingImage).length },
      stopped_containers: {
        candidateBytes: containers.filter((item) => item.State !== 'running').reduce((sum, item) => sum + bytes(item.SizeRw), 0),
        candidateCount: containers.filter((item) => item.State !== 'running').length,
      },
      old_releases: { candidateBytes: sumFiles(releases.oldStable), candidateCount: releases.oldStable.length, files: releases.oldStable },
      temporary_releases: { candidateBytes: sumFiles(releases.temporary), candidateCount: releases.temporary.length, files: releases.temporary },
      archived_logs: { candidateBytes: sumFiles(archivedLogs), candidateCount: archivedLogs.length, files: archivedLogs },
    },
  };
}

function isReleasePublishInProgress(now = Date.now()) {
  const marker = path.join(RELEASES_ROOT, '.publishing');
  if (!fs.existsSync(marker)) return false;
  try { return now - fs.statSync(marker).mtimeMs < MIN_TEMP_AGE_MS; } catch { return false; }
}

function removeListedFiles(root, candidates) {
  let reclaimedBytes = 0;
  const removed = [];
  for (const candidate of candidates) {
    const target = path.resolve(root, candidate.path);
    const relative = path.relative(path.resolve(root), target);
    if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('unsafe_cleanup_path');
    if (!fs.existsSync(target)) continue;
    const stat = fs.statSync(target);
    if (!stat.isFile()) continue;
    fs.unlinkSync(target);
    reclaimedBytes += stat.size;
    removed.push(candidate.path);
  }
  return { reclaimedBytes, removed };
}

async function runCleanup(tasks) {
  const results = {};
  if (tasks.includes('docker_build_cache')) {
    const result = await dockerRequest('POST', '/build/prune?all=1');
    results.docker_build_cache = { reclaimedBytes: bytes(result.SpaceReclaimed), removed: result.CachesDeleted || [] };
  }
  if (tasks.includes('dangling_images')) {
    const filters = encodeURIComponent(JSON.stringify({ dangling: ['true'] }));
    const result = await dockerRequest('POST', `/images/prune?filters=${filters}`);
    results.dangling_images = { reclaimedBytes: bytes(result.SpaceReclaimed), removed: result.ImagesDeleted || [] };
  }
  if (tasks.includes('stopped_containers')) {
    const result = await dockerRequest('POST', '/containers/prune');
    results.stopped_containers = { reclaimedBytes: bytes(result.SpaceReclaimed), removed: result.ContainersDeleted || [] };
  }

  const releaseCandidates = collectReleaseCandidates();
  if (tasks.includes('old_releases')) {
    results.old_releases = removeListedFiles(RELEASES_ROOT, releaseCandidates.oldStable);
  }
  if (tasks.includes('temporary_releases')) {
    results.temporary_releases = removeListedFiles(RELEASES_ROOT, releaseCandidates.temporary);
  }
  if (tasks.includes('archived_logs')) {
    results.archived_logs = removeListedFiles(LOGS_ROOT, collectArchivedLogs());
  }
  return results;
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 32 * 1024) throw new Error('request_too_large');
    chunks.push(chunk);
  }
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/health') return respond(res, 200, { status: 'ok' });
    if (!authorized(req)) return respond(res, 401, { error: 'unauthorized' });
    if (req.method === 'GET' && req.url === '/preview') return respond(res, 200, await buildPreview());
    if (req.method === 'POST' && req.url === '/cleanup') {
      if (cleanupRunning) return respond(res, 409, { error: 'maintenance_already_running' });
      if (isReleasePublishInProgress()) return respond(res, 409, { error: 'release_publish_in_progress' });
      const body = await readBody(req);
      const tasks = Array.isArray(body.tasks)
        ? [...new Set(body.tasks.map(String))].filter((task) => ALLOWED_TASKS.has(task))
        : [];
      if (!tasks.length || tasks.length !== new Set((body.tasks || []).map(String)).size) {
        return respond(res, 400, { error: 'invalid_maintenance_tasks' });
      }
      cleanupRunning = true;
      try {
        const before = await buildPreview();
        const results = await runCleanup(tasks);
        const after = await buildPreview();
        const reclaimedBytes = Object.values(results).reduce((sum, result) => sum + bytes(result.reclaimedBytes), 0);
        return respond(res, 200, { startedAt: before.generatedAt, completedAt: new Date().toISOString(), tasks, reclaimedBytes, results, before, after });
      } finally {
        cleanupRunning = false;
      }
    }
    return respond(res, 404, { error: 'not_found' });
  } catch (error) {
    console.error(JSON.stringify({ level: 'error', event: 'maintenance_agent_error', message: error.message }));
    return respond(res, 500, { error: 'maintenance_agent_failed' });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(JSON.stringify({ level: 'info', event: 'maintenance_agent_started', port: PORT }));
});
