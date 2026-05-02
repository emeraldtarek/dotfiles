#!/usr/bin/env node
/**
 * Generic Playwright crawler for docs-to-md.
 *
 * Reads URLs from ../all-urls.txt and emits one Markdown file per URL into
 * ../full/<slug>.md. The slug is derived from the URL path with `/` → `__`.
 *
 * Resumable: skips files already present (use --force to override).
 *
 *   CONCURRENCY=8 NAV_TIMEOUT=45000 RETRIES=2 node crawl.js
 *
 * Flags:
 *   --force                re-crawl even if file exists
 *   --only=<substring>     only crawl URLs containing this substring
 *   --urls=<path>          alt URL list (default: ../all-urls.txt)
 *   --root=<url>           explicit URL prefix to strip when computing slugs.
 *                          Default = longest common path prefix in the URL list.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { chromium } from 'playwright';

import { extractFnSrc } from './extract.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');
const FULL_DIR = path.join(ROOT, 'full');
const URLS_FILE_DEFAULT = path.join(ROOT, 'all-urls.txt');

const CONCURRENCY = parseInt(process.env.CONCURRENCY || '8', 10);
const NAV_TIMEOUT = parseInt(process.env.NAV_TIMEOUT || '45000', 10);
const RETRIES = parseInt(process.env.RETRIES || '2', 10);
const args = process.argv.slice(2);
const FORCE = args.includes('--force');
const ONLY = (args.find((a) => a.startsWith('--only=')) || '').slice('--only='.length);
const URLS_OVERRIDE = (args.find((a) => a.startsWith('--urls=')) || '').slice('--urls='.length);
const ROOT_OVERRIDE = (args.find((a) => a.startsWith('--root=')) || '').slice('--root='.length);

fs.mkdirSync(FULL_DIR, { recursive: true });

function loadUrls() {
  const file = URLS_OVERRIDE || URLS_FILE_DEFAULT;
  return fs.readFileSync(file, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean);
}

/**
 * Compute the longest common URL prefix that ends at a `/`. Used to build
 * stable slugs when the URL list spans multiple sub-trees of one host.
 */
function longestCommonPrefix(urls) {
  if (!urls.length) return '';
  let prefix = urls[0];
  for (const u of urls.slice(1)) {
    let i = 0;
    const max = Math.min(prefix.length, u.length);
    while (i < max && prefix[i] === u[i]) i++;
    prefix = prefix.slice(0, i);
    if (!prefix.includes('://')) return '';
  }
  // Trim back to last slash so we don't cut a path segment in half.
  const lastSlash = prefix.lastIndexOf('/');
  if (lastSlash < 0) return '';
  return prefix.slice(0, lastSlash + 1);
}

function makeSlugger(allUrls) {
  let rootPrefix = ROOT_OVERRIDE;
  if (!rootPrefix) {
    rootPrefix = longestCommonPrefix(allUrls);
    // For single-host docs with mixed sub-trees, fall back to host root + 1 segment
    // ("https://example.com/docs/").
    if (!rootPrefix) {
      try {
        const u = new URL(allUrls[0]);
        rootPrefix = `${u.protocol}//${u.host}/`;
      } catch {
        rootPrefix = '';
      }
    }
  }
  if (!rootPrefix.endsWith('/')) rootPrefix += '/';
  console.log(`Slug root prefix: ${rootPrefix}`);
  return (url) => {
    let suffix = url.startsWith(rootPrefix) ? url.slice(rootPrefix.length) : url;
    suffix = suffix.replace(/[?#].*$/, '').replace(/\/+$/, '');
    if (!suffix) return '_index';
    return suffix.replace(/\//g, '__');
  };
}

function frontmatter(url, title) {
  const safe = (title || '').replace(/\n/g, ' ').replace(/"/g, "'");
  return `---\nurl: ${url}\ntitle: "${safe}"\n---\n\n`;
}

async function extractFromPage(page, url) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT });
  await page.waitForSelector('article, main', { timeout: NAV_TIMEOUT });
  await page.waitForTimeout(500);

  // Auto-expand "Show ..." disclosure buttons inside the article so nested
  // schema fields are reachable from the DOM.
  await page.evaluate(async () => {
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const article = document.querySelector('article') || document.querySelector('main');
    if (!article) return;
    for (let pass = 0; pass < 4; pass++) {
      const buttons = Array.from(article.querySelectorAll('button')).filter((b) => {
        const t = (b.textContent || '').trim().toLowerCase();
        return /^show\b/.test(t) || /properties$/.test(t) || /attributes$/.test(t);
      });
      if (!buttons.length) break;
      let clicked = 0;
      for (const b of buttons) {
        if (b.getAttribute('data-state') === 'open') continue;
        b.click();
        clicked++;
        await sleep(15);
      }
      if (clicked === 0) break;
      await sleep(120);
    }
  });

  return await page.evaluate(extractFnSrc);
}

async function workerLoop(context, queue, slugFor, stats) {
  const page = await context.newPage();
  await page.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (t === 'image' || t === 'media' || t === 'font') return route.abort();
    return route.continue();
  });

  while (queue.length) {
    const url = queue.shift();
    if (!url) break;
    const fname = slugFor(url);
    const dest = path.join(FULL_DIR, `${fname}.md`);
    if (!FORCE && fs.existsSync(dest)) {
      stats.skipped++;
      continue;
    }
    let lastErr = null;
    let result = null;
    for (let attempt = 0; attempt <= RETRIES; attempt++) {
      try {
        result = await extractFromPage(page, url);
        if (!result || !result.markdown || result.markdown.length < 30) {
          throw new Error(`too short (${result ? result.markdown.length : 0} chars)`);
        }
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
        await page.waitForTimeout(500 * (attempt + 1));
      }
    }
    if (lastErr) {
      stats.fail++;
      const failBody = `url: ${url}\nerror: ${lastErr.message || String(lastErr)}\n`;
      fs.writeFileSync(path.join(FULL_DIR, `${fname}.failed`), failBody);
      process.stdout.write(`✗ ${fname}: ${lastErr.message || lastErr}\n`);
      continue;
    }
    const out = frontmatter(url, result.title || '') + result.markdown + '\n';
    fs.writeFileSync(dest, out);
    stats.ok++;
    const failPath = path.join(FULL_DIR, `${fname}.failed`);
    if (fs.existsSync(failPath)) fs.unlinkSync(failPath);
    process.stdout.write(`✓ ${fname}\n`);
  }

  await page.close();
}

async function main() {
  let urls = loadUrls();
  if (ONLY) urls = urls.filter((u) => u.includes(ONLY));
  const slugFor = makeSlugger(urls);
  const queue = urls.slice();
  const stats = { ok: 0, fail: 0, skipped: 0, total: urls.length };
  console.log(`Crawling ${urls.length} URLs with concurrency=${CONCURRENCY}…`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    viewport: { width: 1280, height: 900 },
  });

  const workers = Array.from({ length: CONCURRENCY }, () =>
    workerLoop(context, queue, slugFor, stats).catch((e) => {
      console.error('worker fatal', e);
    }),
  );
  await Promise.all(workers);

  await context.close();
  await browser.close();

  console.log(
    `Done. ok=${stats.ok} fail=${stats.fail} skipped=${stats.skipped} total=${stats.total}`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
