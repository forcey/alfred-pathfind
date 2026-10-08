#!/usr/bin/env node
// Persistent FFF backend for the PathFind experiment.
// Each Alfred invocation is a short-lived client. This server keeps indices
// resident across queries so the benchmark tests the design FFF is built for.
import { createConnection, createServer } from 'node:net';
import { spawn } from 'node:child_process';
import { mkdirSync, realpathSync, existsSync, unlinkSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceFile = fileURLToPath(import.meta.url);
const cache = join(homedir(), 'Library', 'Caches', 'PathFind-FFF-Experiment');
const socket = join(cache, 'fff.sock');
const command = process.argv[2] || 'search';
const finders = new Map();

function rootsFromEnv() {
  const raw = process.env.PATHFIND_PATHS || process.cwd();
  const roots = raw.split(/\r?\n/).map(x => x.trim()).filter(Boolean).map(x => {
    const expanded = x === '~' ? homedir() : x.startsWith('~/') ? join(homedir(), x.slice(2)) : x;
    const absolute = resolve(expanded);
    try { return realpathSync(absolute); } catch { return absolute; }
  });
  return [...new Set(roots)];
}

async function getFinder(root) {
  if (!finders.has(root)) {
    const building = (async () => {
      const { FileFinder } = await import('@ff-labs/fff-node');
      const result = FileFinder.create({
        basePath: root,
        disableContentIndexing: true,
        disableMmapCache: true,
        enableHomeDirScanning: true,
        followSymlinks: process.env.ALLOW_XDEV === 'true' || process.env.ALLOW_XDEV === '1',
      });
      if (!result.ok) throw Error(root + ': ' + result.error);
      const finder = result.value;
      const scan = await finder.waitForScan(30000);
      if (!scan.ok || !scan.value) throw Error('FFF index not ready at ' + root);
      return finder;
    })().catch(e => { finders.delete(root); throw e; });
    finders.set(root, building);
  }
  return finders.get(root);
}

function matchesLiteralQuery(path, query) {
  // FFF uses typo-tolerant fuzzy matching and may return candidates that
  // PathFind would never return. For ordinary literal queries, preserve the
  // original AND-across-the-full-path behavior before sending to jq.
  // Do not reinterpret advanced FFF operators or regex-like queries here.
  const words = query.toLowerCase().split(/[\\/\s]+/).filter(Boolean);
  if (!words.length) return true;
  if (words.some(w => /[?*\[\]{}()|^$]/.test(w))) return true;
  const lower = path.toLowerCase();
  return words.every(word => lower.includes(word));
}

function matchesExcludes(path, exclusions) {
  const segments = path.split('/');
  return exclusions.some(e => {
    // A simple component name works like the common PathFind exclusions.
    // Complex fd globs do not carry over identically to FFF.
    if (/[*?\[\]]/.test(e)) return false;
    return segments.includes(e.replace(/\/$/, ''));
  });
}

async function handle(req) {
  if (req.op === 'ping') return { ok: true };
  if (req.op === 'stop') {
    setTimeout(() => process.exit(0), 50);
    return { ok: true };
  }
  const roots = Array.isArray(req.roots) ? req.roots.filter(Boolean) : [];
  if (req.op === 'warm') {
    await Promise.all(roots.map(getFinder));
    return { ok: true, roots: roots.length };
  }
  if (req.op !== 'search') return { ok: false, error: 'unknown operation' };
  const started = process.hrtime.bigint();
  const results = await Promise.all(roots.map(async root => {
    const finder = await getFinder(root);
    const options = { pageSize: req.limit || 500 };
    const result = req.mode === 'directory'
      ? finder.directorySearch(req.query, options)
      : req.mode === 'file'
        ? finder.fileSearch(req.query, options)
        : finder.mixedSearch(req.query, options);
    if (!result.ok) throw Error(root + ': ' + result.error);
    return result.value.items.map(entry => {
      const relative = entry.item ? entry.item.relativePath : entry.relativePath;
      return resolve(root, relative.replace(/\/$/, ''));
    });
  }));
  const exclusions = Array.isArray(req.exclude) ? req.exclude : [];
  const hits = [...new Set(results.flat())].filter(p => {
    if (!req.includeHidden && p.split('/').some((s, i) => i > 0 && s.startsWith('.'))) return false;
    return matchesLiteralQuery(p, req.query) && !matchesExcludes(p, exclusions);
  });
  return { ok: true, hits, took_us: Number((process.hrtime.bigint() - started) / 1000n) };
}

async function serve() {
  mkdirSync(cache, { recursive: true, mode: 0o700 });
  const server = createServer(conn => {
    let buffer = '';
    conn.setEncoding('utf8');
    conn.on('data', chunk => {
      buffer += chunk;
      const newline = buffer.indexOf('\n');
      if (newline < 0) return;
      const line = buffer.slice(0, newline);
      buffer = '';
      let req;
      try { req = JSON.parse(line); } catch { conn.end(JSON.stringify({ok:false,error:'bad JSON'}) + '\n'); return; }
      Promise.resolve().then(() => handle(req)).catch(e => ({ok:false,error:String(e.message || e)}))
        .then(res => conn.end(JSON.stringify(res) + '\n'));
    });
  });
  server.on('error', e => {
    console.error('fff server:', e.message);
    process.exit(1);
  });
  server.listen(socket);
}

function request(req, timeoutMs = 12000) {
  return new Promise((resolveReq, reject) => {
    const conn = createConnection(socket);
    let buffer = '';
    const timer = setTimeout(() => { conn.destroy(); reject(Error('FFF backend timeout')); }, timeoutMs);
    const finish = (error, result) => {
      clearTimeout(timer);
      if (error) reject(error); else resolveReq(result);
    };
    conn.once('error', error => finish(error));
    conn.setEncoding('utf8');
    conn.once('connect', () => conn.write(JSON.stringify(req) + '\n'));
    conn.on('data', chunk => {
      buffer += chunk;
      const i = buffer.indexOf('\n');
      if (i >= 0) {
        try { finish(null, JSON.parse(buffer.slice(0, i))); }
        catch (e) { finish(e); }
        conn.end();
      }
    });
    conn.on('end', () => { if (!buffer.includes('\n')) finish(Error('FFF server disconnected')); });
  });
}

async function client() {
  const req = command === 'warm' ? {op:'warm'} : command === 'stop' ? {op:'stop'} : {op:'search'};
  if (command === 'search') {
    req.query = process.argv[3] || '';
    req.mode = process.argv[4] || '';
    req.limit = 500;
    req.includeHidden = ['true','1'].includes((process.env.INCLUDE_HIDDEN || '').toLowerCase());
    req.exclude = (process.env.PATHFIND_EXCLUDE || '').split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  }
  req.roots = rootsFromEnv();
  if (command !== 'stop') {
    try { await request({op:'ping'}, 800); }
    catch {
      mkdirSync(cache, {recursive:true,mode:0o700});
      if (existsSync(socket)) {
        try { unlinkSync(socket); } catch {}
      }
      spawn(process.execPath, [sourceFile, 'serve'], {
        detached: true, stdio: 'ignore', env: process.env,
      }).unref();
      let ready = false;
      for (let tries = 0; tries < 70; tries++) {
        await new Promise(done => setTimeout(done, 60));
        try { await request({op:'ping'}, 600); ready = true; break; } catch {}
      }
      if (!ready) throw Error('FFF server could not start (check npm dependencies)');
    }
  }
  const result = await request(req, command === 'warm' ? 90000 : 35000);
  if (!result.ok) throw Error(result.error || 'FFF search failed');
  if (command === 'search') process.stdout.write(result.hits.join('\n') + (result.hits.length ? '\n' : ''));
  else console.log(JSON.stringify(result));
}

if (command === 'serve') {
  serve().catch(e => { console.error(e); process.exitCode = 1; });
} else {
  client().catch(e => { console.error('PathFind FFF:', e.message); process.exitCode = 1; });
}
