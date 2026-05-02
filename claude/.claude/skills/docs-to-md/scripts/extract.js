/**
 * In-page extractor for Fern docs (ElevenLabs).
 *
 * Detects two layouts:
 *   1. API reference (`.fern-layout-reference-content`) — produces structured
 *      Markdown for endpoint, headers/path/query/body params, response, errors,
 *      and code samples.
 *   2. Standard prose (`.fern-prose` / generic article) — converts HTML to
 *      Markdown using a hand-rolled walker that preserves headings, lists,
 *      tables, code blocks, blockquotes, links, and images.
 *
 * Returns { title, markdown }. Designed to be evaluated inside `page.evaluate()`.
 */

export const extractFn = function () {
  // -----------------------------------------------------------
  // Generic HTML -> Markdown walker
  // -----------------------------------------------------------
  function isBlock(tag) {
    return /^(p|div|section|article|header|footer|main|aside|h1|h2|h3|h4|h5|h6|ul|ol|li|table|thead|tbody|tfoot|tr|td|th|pre|blockquote|hr|details|summary)$/.test(
      tag,
    );
  }

  function inlineText(node) {
    return walk(node, { listDepth: 0, inPre: false }).trim().replace(/\s+/g, ' ');
  }

  // Render a <pre> code block.
  // Fern's code blocks use a <table.code-block-line-group> with line-number gutter cells.
  // Strip those, take only the line-content cells, and join with newlines.
  function renderPre(preEl) {
    // Detect language from any nested element with "language-XYZ" class.
    let lang = '';
    const langMatcher = /language-([\w+-]+)/;
    const codeEl = preEl.querySelector('code');
    if (codeEl) {
      const m = (codeEl.className || '').match(langMatcher);
      if (m) lang = m[1];
    }
    if (!lang) {
      // Fern carries the language label as a tab nearby; try data-language attr.
      const dl = preEl.getAttribute('data-language') || '';
      if (dl) lang = dl;
    }
    if (!lang) {
      // Look at sibling tab labels (cURL/Python/etc.) — bubble up.
      let sib = preEl.parentElement;
      let depth = 0;
      while (sib && depth < 5) {
        const tabActive = sib.querySelector(
          '[data-state="active"], [aria-selected="true"]',
        );
        if (tabActive) {
          const t = tabActive.textContent.trim().toLowerCase();
          if (t.match(/^[a-z+#-]{1,15}$/)) lang = t;
          break;
        }
        sib = sib.parentElement;
        depth++;
      }
    }
    // Map common labels to standard fences
    const langMap = {
      curl: 'bash',
      shell: 'bash',
      sh: 'bash',
      python: 'python',
      js: 'javascript',
      javascript: 'javascript',
      ts: 'typescript',
      typescript: 'typescript',
      go: 'go',
      ruby: 'ruby',
      php: 'php',
      java: 'java',
      csharp: 'csharp',
      cs: 'csharp',
      rust: 'rust',
      json: 'json',
      yaml: 'yaml',
      yml: 'yaml',
      http: 'http',
      bash: 'bash',
    };
    if (langMap[lang]) lang = langMap[lang];

    // Try the table-based line layout first
    const lineRows = preEl.querySelectorAll(
      'table.code-block-line-group tr.code-block-line',
    );
    let text;
    if (lineRows.length) {
      text = Array.from(lineRows)
        .map((tr) => {
          const content = tr.querySelector('td.code-block-line-content');
          if (!content) return '';
          // textContent already concatenates token spans without their styles.
          return content.textContent;
        })
        .join('\n');
    } else if (codeEl) {
      text = codeEl.textContent;
    } else {
      // Fall back: clone, drop <style> tags, then take textContent.
      const clone = preEl.cloneNode(true);
      clone.querySelectorAll('style').forEach((s) => s.remove());
      // Remove gutter cells if any
      clone.querySelectorAll('.code-block-line-gutter').forEach((g) => g.remove());
      text = clone.textContent;
    }
    text = (text || '').replace(/\n+$/, '');
    return '\n```' + lang + '\n' + text + '\n```';
  }

  function walk(node, ctx) {
    if (!node) return '';
    if (node.nodeType === 3) return node.textContent;
    if (node.nodeType !== 1) return '';
    const tag = node.tagName.toLowerCase();
    if (tag === 'script' || tag === 'style' || tag === 'noscript') return '';
    // Skip Radix scroll-area style helpers
    if (node.dataset && node.dataset.radixScrollAreaViewport === '') {
      return Array.from(node.children).map((c) => walk(c, ctx)).join('');
    }
    // Skip "Copy" / "Try it" buttons and other UI controls
    if (tag === 'button') return '';
    // Skip chevron / decorative svgs
    if (tag === 'svg') return '';
    // Skip aria-hidden
    if (node.getAttribute('aria-hidden') === 'true') return '';
    // Strip the leading ".fa-secondary{opacity:.4}" CSS-in-text artifact (Font Awesome inline)
    // by recursing through children only.

    const children = Array.from(node.childNodes);
    const childMd = children.map((c) => walk(c, ctx)).join('');

    switch (tag) {
      case 'h1': return '\n# ' + childMd.trim() + '\n\n';
      case 'h2': return '\n## ' + childMd.trim() + '\n\n';
      case 'h3': return '\n### ' + childMd.trim() + '\n\n';
      case 'h4': return '\n#### ' + childMd.trim() + '\n\n';
      case 'h5': return '\n##### ' + childMd.trim() + '\n\n';
      case 'h6': return '\n###### ' + childMd.trim() + '\n\n';
      case 'p': {
        const t = childMd.trim();
        return t ? t + '\n\n' : '';
      }
      case 'br': return '\n';
      case 'strong':
      case 'b':
        return '**' + childMd + '**';
      case 'em':
      case 'i':
        return '*' + childMd + '*';
      case 'code': {
        if (ctx.inPre) return childMd;
        return '`' + childMd.replace(/`/g, '\\`') + '`';
      }
      case 'pre': {
        return renderPre(node) + '\n\n';
      }
      case 'a': {
        const href = node.getAttribute('href') || '';
        const text = childMd.trim();
        if (!text) return '';
        if (!href) return text;
        return '[' + text + '](' + href + ')';
      }
      case 'ul':
      case 'ol': {
        const items = Array.from(node.children).filter((c) => c.tagName === 'LI');
        const lines = items.map((li, i) => {
          const inner = walk(li, { ...ctx, listDepth: ctx.listDepth + 1 }).trim();
          const prefix = tag === 'ol' ? `${i + 1}. ` : '- ';
          // Indent multi-line content
          const indent = '  '.repeat(ctx.listDepth);
          const content = inner
            .split('\n')
            .map((ln, idx) => (idx === 0 ? indent + prefix + ln : indent + '  ' + ln))
            .join('\n');
          return content;
        });
        return '\n' + lines.join('\n') + '\n\n';
      }
      case 'li':
        return childMd;
      case 'table': {
        const rows = Array.from(node.querySelectorAll('tr'));
        if (!rows.length) return '';
        const data = rows.map((row) =>
          Array.from(row.querySelectorAll('th,td')).map((c) =>
            inlineText(c).replace(/\|/g, '\\|').replace(/\n/g, ' '),
          ),
        );
        const numCols = Math.max(...data.map((r) => r.length));
        if (numCols === 0) return '';
        const lines = data.map((r) => {
          const padded = r.concat(Array(numCols - r.length).fill(''));
          return '| ' + padded.join(' | ') + ' |';
        });
        lines.splice(1, 0, '| ' + Array(numCols).fill('---').join(' | ') + ' |');
        return '\n' + lines.join('\n') + '\n\n';
      }
      case 'th':
      case 'td':
      case 'tr':
      case 'thead':
      case 'tbody':
      case 'tfoot':
        return childMd;
      case 'img': {
        const src = node.getAttribute('src') || '';
        const alt = (node.getAttribute('alt') || '').replace(/\n/g, ' ');
        if (!src) return '';
        return '![' + alt + '](' + src + ')';
      }
      case 'blockquote':
        return (
          '\n' +
          childMd
            .trim()
            .split('\n')
            .map((l) => '> ' + l)
            .join('\n') +
          '\n\n'
        );
      case 'hr':
        return '\n---\n\n';
      case 'details': {
        const summary = node.querySelector(':scope > summary');
        const summaryText = summary ? inlineText(summary) : 'Show';
        const restNodes = Array.from(node.childNodes).filter(
          (c) => !(c.nodeType === 1 && c.tagName === 'SUMMARY'),
        );
        const inner = restNodes.map((c) => walk(c, ctx)).join('').trim();
        return '\n<details>\n<summary>' + summaryText + '</summary>\n\n' + inner + '\n\n</details>\n\n';
      }
      case 'summary':
        return childMd;
      default: {
        if (isBlock(tag)) return childMd;
        return childMd;
      }
    }
  }

  function htmlToMd(rootEl) {
    let md = walk(rootEl, { listDepth: 0, inPre: false });
    // Cleanups
    md = md.replace(/ /g, ' ');
    md = md.replace(/\.fa-secondary\{opacity:\.4\}/g, '');
    md = md.replace(/\[data-radix-scroll-area-viewport\][^]*?display:none\}/g, '');
    md = md.replace(/\n{3,}/g, '\n\n').trim();
    return md;
  }

  // -----------------------------------------------------------
  // API reference layout extractor
  // -----------------------------------------------------------
  function extractApiRef(article) {
    const out = [];

    // 1. Header (path / breadcrumb / title / method+url)
    const header = article.querySelector('header');
    let title = '';
    if (header) {
      const h1 = header.querySelector('h1');
      title = h1 ? h1.textContent.trim() : '';
      if (title) out.push('# ' + title + '\n');
      // Method comes from a `<span class="fern-docs-badge ...">GET</span>` (etc).
      let method = '';
      const badge = header.querySelector('.fern-docs-badge');
      if (badge) {
        const t = badge.textContent.trim().toUpperCase();
        if (/^(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)$/.test(t)) method = t;
      }
      if (!method) {
        const m = (header.textContent || '').match(/\b(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\b/);
        if (m) method = m[1];
      }
      // URL is in a `<span class="font-mono ...">https://...</span>` element.
      let url = '';
      const monoSpans = Array.from(header.querySelectorAll('.font-mono, code'));
      for (const c of monoSpans) {
        const t = c.textContent.trim();
        if (/^https?:\/\//.test(t)) { url = t; break; }
        if (t.startsWith('/v')) { url = t; break; }
      }
      if (!url) {
        const m = (header.textContent || '').match(/https?:\/\/\S+/);
        if (m) url = m[0];
      }
      if (method && url) {
        out.push('```http\n' + method + ' ' + url + '\n```\n');
      }
    }

    // 2. Endpoint description (top-most prose under reference content)
    const desc = article.querySelector(
      '.fern-layout-reference-content > div.fern-prose > div > div.fern-prose:first-child, .fern-layout-reference-content > div > div > div.fern-prose:first-child',
    );
    if (desc) {
      const txt = inlineText(desc);
      if (txt) out.push(txt + '\n');
    }

    // 3. Sections — Headers / Path / Query / Body / Response / Errors
    const sectionMap = [
      ['fern-endpoint-section-headers', 'Headers'],
      ['fern-endpoint-section-path-parameters', 'Path parameters'],
      ['fern-endpoint-section-query-parameters', 'Query parameters'],
      ['fern-endpoint-section-request-body', 'Request body'],
      ['fern-endpoint-section-request', 'Request'],
      ['fern-endpoint-section-response-body', 'Response'],
      ['fern-endpoint-section-response', 'Response'],
      ['fern-endpoint-section-errors', 'Errors'],
    ];

    for (const [cls, label] of sectionMap) {
      const sections = article.querySelectorAll('.' + cls);
      sections.forEach((sec) => {
        out.push('## ' + label + '\n');
        renderParamSection(sec, out, 0);
      });
    }

    // 4. Code samples from <aside>
    const aside = article.querySelector('aside.fern-layout-reference-aside');
    if (aside) {
      const pres = Array.from(aside.querySelectorAll('pre'));
      if (pres.length) {
        out.push('## Examples\n');
        pres.forEach((pre, idx) => {
          // Heuristic: first PRE is the request, last is example response
          const heading = pres.length > 1 && idx === pres.length - 1 ? 'Response' : 'Request';
          out.push('### ' + heading + '\n');
          out.push(renderPre(pre).trim() + '\n');
        });
      }
    }

    return { title, markdown: out.join('\n').replace(/\n{3,}/g, '\n\n').trim() };
  }

  function renderParamSection(secEl, out, depth) {
    // Find direct children that look like parameter blocks: id contains '#request.' or '#response.' or '#error.'
    const params = Array.from(secEl.children).filter((c) => {
      if (c.tagName !== 'DIV') return false;
      const id = c.id || '';
      return /#(request|response|error)\b/.test(id);
    });
    if (params.length === 0) {
      // Errors section uses a different layout: each child is an error card with
      // the status code and description concatenated. Try to detect a 3-digit code.
      const errorCards = Array.from(secEl.querySelectorAll(':scope > div > div'));
      if (errorCards.length) {
        errorCards.forEach((card) => {
          const t = inlineText(card);
          if (!t) return;
          const m = t.match(/^(\d{3})\s*(.*)$/);
          if (m) out.push('- **' + m[1] + '** — ' + m[2]);
          else out.push('- ' + t);
        });
        out.push('');
      }
      return;
    }
    params.forEach((p) => renderParam(p, out, depth));
  }

  function renderParam(paramEl, out, depth) {
    const indent = '  '.repeat(depth);
    const heading = depth === 0 ? '###' : depth === 1 ? '####' : '#####';

    // Name
    const nameEl = paramEl.querySelector('.fern-api-property-key');
    const name = nameEl ? nameEl.textContent.trim() : '';

    // Type, optional, default, constraint
    const typeEl = paramEl.querySelector('.fern-api-property-type');
    const optEl = paramEl.querySelector('.fern-api-property-optional');
    const reqEl = paramEl.querySelector('.fern-api-property-required');
    const defEl = paramEl.querySelector('.fern-api-property-default');
    const conEl = paramEl.querySelector('.fern-api-property-constraint');

    const type = typeEl ? typeEl.textContent.trim() : '';
    const optional = optEl ? 'Optional' : reqEl ? 'Required' : '';
    const def = defEl ? defEl.textContent.trim() : '';
    const con = conEl ? conEl.textContent.trim() : '';

    const meta = [type, optional, con, def].filter(Boolean).join(' · ');
    if (depth === 0) {
      out.push(heading + ' `' + name + '`' + (meta ? ' — ' + meta : '') + '\n');
    } else {
      // Nested fields — use bullet-style for compactness
      out.push(indent + '- **`' + name + '`**' + (meta ? ' — ' + meta : ''));
    }

    // Description (only direct child fern-prose, not nested ones)
    const directProse = Array.from(paramEl.children).find(
      (c) => c.tagName === 'DIV' && c.classList.contains('fern-prose') && !c.id,
    );
    if (directProse) {
      const descMd = htmlToMd(directProse).trim();
      if (descMd) {
        if (depth === 0) {
          out.push(descMd + '\n');
        } else {
          // Indent description under bullet
          const indented = descMd.split('\n').map((l) => indent + '  ' + l).join('\n');
          out.push(indented);
        }
      }
    }

    // Allowed values (enum) appear as a follow-up div with "Allowed values:" + chips
    const allowedDiv = Array.from(paramEl.querySelectorAll(':scope > div')).find((d) =>
      /Allowed values:/.test(d.textContent || ''),
    );
    if (allowedDiv) {
      const codes = Array.from(allowedDiv.querySelectorAll('code')).map((c) => '`' + c.textContent.trim() + '`');
      if (codes.length) {
        const line = (depth === 0 ? '' : indent + '  ') + 'Allowed values: ' + codes.join(', ');
        out.push(line + '\n');
      }
    }

    // Nested object/array fields via "Show ..." expandable.
    // The expansion content lives in a sibling div with role="region" or in a div containing
    // further nested params with id "...request.body.foo.bar".
    const nested = Array.from(paramEl.querySelectorAll(':scope > div'))
      .flatMap((d) => Array.from(d.querySelectorAll(':scope > div')))
      .filter((d) => /#(request|response|error)\b.*\..*\./.test(d.id || ''));

    nested.forEach((n) => {
      // Avoid double-rendering: only render direct nested children one level deeper.
      const myId = paramEl.id || '';
      const nId = n.id || '';
      if (myId && nId.startsWith(myId + '.')) {
        const remainder = nId.slice(myId.length + 1);
        if (!remainder.includes('.')) {
          renderParam(n, out, depth + 1);
        }
      }
    });
  }

  // -----------------------------------------------------------
  // Top-level dispatch
  // -----------------------------------------------------------
  function findArticle() {
    return (
      document.querySelector('article.fern-mdx') ||
      document.querySelector('article#fern-content') ||
      document.querySelector('article') ||
      document.querySelector('main')
    );
  }

  const article = findArticle();
  if (!article) return { title: '', markdown: '', error: 'no article element' };

  // Strip helpers we never want
  const clone = article.cloneNode(true);
  for (const sel of [
    '.fern-feedback',
    '[class*="feedback"]',
    'footer',
    '[data-state="closed"][role="dialog"]',
  ]) {
    clone.querySelectorAll(sel).forEach((n) => n.remove());
  }

  const isApiRef = !!clone.querySelector('.fern-layout-reference-content');
  if (isApiRef) {
    const r = extractApiRef(clone);
    if (r.markdown && r.markdown.length > 80) return r;
    // Fall through to generic if the API ref extractor produced too little
  }

  // Generic
  const titleEl = clone.querySelector('h1');
  const title = titleEl
    ? titleEl.textContent.trim()
    : (document.title || '').replace(/\s*\|\s*ElevenLabs.*$/, '').trim();
  const md = htmlToMd(clone);
  return { title, markdown: md };
};

export const extractFnSrc =
  '(' + extractFn.toString() + ')()';
