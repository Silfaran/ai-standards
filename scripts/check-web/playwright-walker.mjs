#!/usr/bin/env node
// Playwright walker for /check-web.
// Deterministic crawl of a base URL, captures runtime symptoms (console,
// network, page errors, axe violations) per visited route, dumps a single
// JSON file. Performs GET navigation + safe clicks (links, tabs, accordions,
// pagination, filter selects). NEVER submits forms. NEVER triggers POST/DELETE.
//
// Usage:
//   node playwright-walker.mjs --url <base> --out <json> \
//        [--routes <file>] [--cookie key=value]... \
//        [--max-depth N] [--max-routes N]

import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import fs from 'node:fs/promises';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));
if (!args.url || !args.out) {
  console.error('Missing --url or --out');
  process.exit(1);
}

const MAX_DEPTH = parseInt(args['max-depth'] ?? '2', 10);
const MAX_ROUTES = parseInt(args['max-routes'] ?? '50', 10);
const COOKIES = (args.cookie ?? []).map(parseCookie);

const startedAt = new Date().toISOString();
const findings = {
  walker_version: '1.0.0',
  started_at: startedAt,
  base_url: args.url,
  config: { max_depth: MAX_DEPTH, max_routes: MAX_ROUTES, has_routes_file: !!args.routes, cookie_count: COOKIES.length },
  routes: [],
  walker_errors: [],
};

const explicitRoutes = args.routes ? await loadRoutes(args.routes, args.url) : null;

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ ignoreHTTPSErrors: true });
if (COOKIES.length > 0) {
  await context.addCookies(COOKIES.map(c => ({ ...c, url: args.url })));
}

const queue = explicitRoutes ?? [{ url: args.url, depth: 0 }];
const visited = new Set();

while (queue.length > 0 && findings.routes.length < MAX_ROUTES) {
  const next = queue.shift();
  if (visited.has(next.url)) continue;
  visited.add(next.url);

  const route = await visitRoute(context, next.url);
  findings.routes.push(route);

  if (!explicitRoutes && next.depth < MAX_DEPTH && route.discovered_links.length > 0) {
    for (const link of route.discovered_links) {
      if (!visited.has(link) && sameOrigin(link, args.url)) {
        queue.push({ url: link, depth: next.depth + 1 });
      }
    }
  }
}

findings.finished_at = new Date().toISOString();
findings.summary = summarize(findings);

await fs.mkdir(path.dirname(args.out), { recursive: true });
await fs.writeFile(args.out, JSON.stringify(findings, null, 2));

await browser.close();

console.log(`Visited ${findings.routes.length} routes. Summary:`);
console.log(`  ${findings.summary.routes_with_5xx} routes with 5xx`);
console.log(`  ${findings.summary.routes_with_4xx_subresources} routes with 4xx subresources`);
console.log(`  ${findings.summary.total_console_errors} console errors`);
console.log(`  ${findings.summary.total_page_errors} page errors`);
console.log(`  ${findings.summary.total_axe_violations} axe violations`);

// ---------------------------------------------------------------------------

async function visitRoute(context, url) {
  const page = await context.newPage();
  const consoleMessages = [];
  const networkResponses = [];
  const pageErrors = [];

  page.on('console', msg => {
    consoleMessages.push({
      level: msg.type(),
      text: msg.text(),
      location: msg.location(),
    });
  });

  page.on('response', async resp => {
    networkResponses.push({
      url: resp.url(),
      method: resp.request().method(),
      status: resp.status(),
      content_type: resp.headers()['content-type'] ?? null,
      from_cache: resp.fromServiceWorker?.() ?? false,
    });
  });

  page.on('pageerror', err => {
    pageErrors.push({ message: err.message, stack: err.stack ?? null });
  });

  const route = {
    url,
    started_at: new Date().toISOString(),
    document_status: null,
    console: consoleMessages,
    network: networkResponses,
    page_errors: pageErrors,
    axe_violations: [],
    discovered_links: [],
    safe_click_results: [],
    walker_error: null,
  };

  try {
    const docResp = await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    route.document_status = docResp ? docResp.status() : null;

    route.discovered_links = await page.$$eval('a[href]', as =>
      as.map(a => a.href).filter(h => h.startsWith('http'))
    );

    route.safe_click_results = await performSafeClicks(page);

    try {
      const axe = await new AxeBuilder({ page }).analyze();
      route.axe_violations = axe.violations.map(v => ({
        id: v.id,
        impact: v.impact,
        help: v.help,
        nodes_count: v.nodes.length,
        sample_target: v.nodes[0]?.target ?? null,
      }));
    } catch (err) {
      route.axe_violations = [];
      route.walker_error = `axe: ${err.message}`;
    }
  } catch (err) {
    route.walker_error = err.message;
  } finally {
    route.finished_at = new Date().toISOString();
    await page.close();
  }

  return route;
}

// Safe click vocabulary: tabs, accordions, expanders, pagination, filter
// selects. NEVER buttons inside forms, NEVER submit, NEVER delete-icon.
async function performSafeClicks(page) {
  const results = [];
  const selectors = [
    '[role="tab"]:not([aria-selected="true"])',
    'button[aria-expanded="false"]',
    '[role="button"][aria-expanded="false"]',
    'nav [aria-label*="page" i] button',
  ];
  for (const sel of selectors) {
    const elements = await page.$$(sel);
    for (let i = 0; i < Math.min(elements.length, 3); i++) {
      try {
        await elements[i].click({ timeout: 2000 });
        await page.waitForTimeout(200);
        results.push({ selector: sel, index: i, ok: true });
      } catch (err) {
        results.push({ selector: sel, index: i, ok: false, error: err.message });
      }
    }
  }
  return results;
}

function summarize(findings) {
  let routes_with_5xx = 0;
  let routes_with_4xx_subresources = 0;
  let total_console_errors = 0;
  let total_page_errors = 0;
  let total_axe_violations = 0;

  for (const r of findings.routes) {
    if (r.document_status && r.document_status >= 500) routes_with_5xx++;
    if (r.network.some(n => n.status >= 400 && n.status < 500 && n.url !== r.url)) {
      routes_with_4xx_subresources++;
    }
    total_console_errors += r.console.filter(c => c.level === 'error').length;
    total_page_errors += r.page_errors.length;
    total_axe_violations += r.axe_violations.reduce((s, v) => s + v.nodes_count, 0);
  }

  return { routes_with_5xx, routes_with_4xx_subresources, total_console_errors, total_page_errors, total_axe_violations };
}

function sameOrigin(a, b) {
  try {
    return new URL(a).origin === new URL(b).origin;
  } catch {
    return false;
  }
}

async function loadRoutes(file, base) {
  const text = await fs.readFile(file, 'utf8');
  return text
    .split('\n')
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'))
    .map(l => ({ url: l.startsWith('http') ? l : new URL(l, base).toString(), depth: 0 }));
}

function parseCookie(s) {
  const i = s.indexOf('=');
  if (i < 0) throw new Error(`Invalid --cookie ${s}, expected key=value`);
  return { name: s.slice(0, i), value: s.slice(i + 1) };
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const val = argv[i + 1];
    if (key === 'cookie') {
      out.cookie = out.cookie ?? [];
      out.cookie.push(val);
    } else {
      out[key] = val;
    }
    i++;
  }
  return out;
}
