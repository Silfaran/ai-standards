#!/usr/bin/env node
/**
 * Sync repo source files into the Starlight content collection.
 *
 * The single source of truth for agent / command / critical-path / project-doc
 * content lives at the repo root. This site does NOT duplicate that content —
 * it imports it on every build via this script so the published docs cannot
 * drift from the framework. The synced files are gitignored under
 * `docs/src/content/docs/` and regenerated on every `npm run dev` /
 * `npm run build` (declared in `docs/package.json`'s `scripts.sync`).
 *
 * Glob-based, so adding a new agent / command / critical-path file requires
 * NO changes here — the next build picks it up automatically. Adding a new
 * source category (e.g. `templates/` rendered as docs) requires extending
 * the `JOBS` array below.
 *
 * Each sync job:
 *   - Reads matching files from a source directory (relative to repo root).
 *   - Prepends a Starlight frontmatter block (title, description) derived
 *     from the file's first H1 / first paragraph.
 *   - Writes to a target directory under `src/content/docs/`.
 *
 * Run `node scripts/sync.mjs` standalone to regenerate without rebuilding.
 */

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, basename, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const DOCS_ROOT = resolve(__dirname, '..', 'src', 'content', 'docs');

/**
 * @typedef {Object} SyncJob
 * @property {string} sourceDir            Directory relative to REPO_ROOT (e.g. 'agents').
 * @property {string} targetDir            Directory relative to DOCS_ROOT (e.g. 'reference/agents').
 * @property {(name: string, body: string) => { title: string, description?: string, slugOverride?: string }} extractMeta
 *           Function that derives Starlight frontmatter from the source filename + body.
 * @property {(name: string) => boolean} [filter] Optional filter — return false to skip a file.
 * @property {(name: string) => string} [renameTo] Optional renamer; receives the source basename.
 */

/** @type {SyncJob[]} */
const JOBS = [
  {
    sourceDir: 'agents',
    targetDir: 'reference/agents',
    filter: (name) => name.endsWith('-agent.md'),
    renameTo: (name) => name.replace(/-agent\.md$/, '.md'),
    extractMeta: (name, body) => {
      const slug = name.replace(/-agent\.md$/, '');
      const title = titleCase(slug.replace(/-/g, ' ')) + ' agent';
      const description = firstParagraphAfter(body, '## Role') ?? `${title} reference.`;
      return { title, description };
    },
  },
  {
    sourceDir: 'commands',
    targetDir: 'reference/commands',
    filter: (name) => name.endsWith('-command.md'),
    renameTo: (name) => name.replace(/-command\.md$/, '.md'),
    extractMeta: (name, body) => {
      const slug = name.replace(/-command\.md$/, '');
      const title = `/${slug}`;
      const description = firstParagraphAfter(body, '## Description') ?? `\`/${slug}\` command reference.`;
      return { title, description };
    },
  },
  {
    sourceDir: join('standards', 'critical-paths'),
    targetDir: 'reference/critical-paths',
    filter: (name) => name.endsWith('.md') && name !== 'README.md',
    extractMeta: (name, body) => {
      const slug = name.replace(/\.md$/, '');
      const titleFromH1 = firstH1(body);
      const title = titleFromH1 ?? `Critical path: ${slug}`;
      const description = firstParagraphAfter(body, '# ') ?? `Critical path for ${slug} diffs.`;
      return { title, description };
    },
  },
  {
    sourceDir: '.',
    targetDir: 'project',
    filter: (name) => ['ARCHITECTURE.md', 'USAGE.md', 'CHANGELOG.md'].includes(name),
    renameTo: (name) => name.toLowerCase(),
    extractMeta: (name, body) => {
      const slug = name.replace(/\.md$/, '').toLowerCase();
      const title =
        slug === 'architecture' ? 'Architecture (deep dive)' :
        slug === 'usage' ? 'Usage guide (complete)' :
        slug === 'changelog' ? 'Changelog' :
        titleCase(slug);
      const description = firstParagraphAfter(body, '# ') ?? `${title}.`;
      return { title, description };
    },
  },
];

function firstH1(body) {
  const m = body.match(/^#\s+(.+?)\s*$/m);
  return m ? m[1].trim() : null;
}

function firstParagraphAfter(body, marker) {
  const idx = body.indexOf(marker);
  const start = idx === -1 ? 0 : idx + marker.length;
  const slice = body.slice(start);
  // first non-empty paragraph (skip leading blank lines + heading line itself)
  const lines = slice.split(/\r?\n/);
  let paragraph = [];
  let started = false;
  for (const line of lines) {
    const t = line.trim();
    if (!started && t === '') continue;
    if (!started && t.startsWith('#')) continue;
    if (t === '' && started) break;
    if (t.startsWith('#') && started) break;
    started = true;
    paragraph.push(t);
  }
  if (paragraph.length === 0) return null;
  // collapse to one paragraph and trim Markdown emphasis markers, links to plain text
  return paragraph
    .join(' ')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

function titleCase(s) {
  return s.replace(/\b\w/g, (c) => c.toUpperCase());
}

function escapeYamlString(s) {
  // Always quote with double quotes; escape embedded double quotes + backslashes.
  return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

function rewriteRelativeLinks(body, sourceFilePath) {
  // Source files use repo-relative links like `../standards/foo.md` or
  // `[CLAUDE.md](CLAUDE.md)`. After sync the file lives under
  // docs/src/content/docs/<targetDir>/. The links must point either:
  //   - into the synced site (when we have a synced target for the link), or
  //   - back to the GitHub source (for unsynced files).
  //
  // Strategy: for every relative .md link, if the target is in our SYNCED_MAP,
  // rewrite to the site-relative slug; otherwise rewrite to the GitHub source URL.
  return body.replace(
    /\]\(([^)]+\.md(?:#[^)]*)?)\)/g,
    (match, target) => {
      if (target.startsWith('http')) return match;
      // Resolve target relative to the source file's directory, then map to repo root.
      const sourceDir = dirname(sourceFilePath);
      const resolved = resolve(sourceDir, target.split('#')[0]);
      const repoRelative = resolved.startsWith(REPO_ROOT) ? resolved.slice(REPO_ROOT.length + 1) : resolved;
      const fragment = target.includes('#') ? '#' + target.split('#')[1] : '';
      // GitHub source URL fallback. Anything not in the synced map gets a GitHub link.
      const ghUrl = `https://github.com/Silfaran/ai-standards/blob/master/${repoRelative}${fragment}`;
      return `](${ghUrl})`;
    },
  );
}

function syncJob(job) {
  const sourceAbs = join(REPO_ROOT, job.sourceDir);
  const targetAbs = join(DOCS_ROOT, job.targetDir);

  // Wipe the target dir so removed source files do not linger as ghost docs.
  if (existsSync(targetAbs)) {
    rmSync(targetAbs, { recursive: true, force: true });
  }
  mkdirSync(targetAbs, { recursive: true });

  const entries = readdirSync(sourceAbs).filter((e) => !job.filter || job.filter(e));
  let count = 0;
  for (const sourceName of entries) {
    const sourcePath = join(sourceAbs, sourceName);
    const sourceBody = readFileSync(sourcePath, 'utf-8');
    const meta = job.extractMeta(sourceName, sourceBody);
    const finalName = job.renameTo ? job.renameTo(sourceName) : sourceName;
    const targetPath = join(targetAbs, finalName);

    // Strip any pre-existing leading H1 — Starlight renders the title from
    // frontmatter and a duplicate H1 looks ugly.
    const bodyWithoutH1 = sourceBody.replace(/^#\s+.+\n+/, '');
    const bodyWithRewrittenLinks = rewriteRelativeLinks(bodyWithoutH1, sourcePath);

    const frontmatter = [
      '---',
      `title: ${escapeYamlString(meta.title)}`,
      meta.description ? `description: ${escapeYamlString(meta.description)}` : null,
      '---',
      '',
      '> Synced verbatim from the repo on every site build. Edit the source file on GitHub (link in the page footer); do not edit the rendered copy here.',
      '',
    ]
      .filter(Boolean)
      .join('\n');

    writeFileSync(targetPath, frontmatter + '\n' + bodyWithRewrittenLinks);
    count++;
  }
  console.log(`  ✓ ${job.sourceDir} → ${job.targetDir} (${count} file${count === 1 ? '' : 's'})`);
}

console.log('docs sync — pulling content from repo sources …');
for (const job of JOBS) {
  syncJob(job);
}
console.log('docs sync — done.');
