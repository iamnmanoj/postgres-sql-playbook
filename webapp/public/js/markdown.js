// Markdown → DOM with playbook-aware links, query-id links, SQL highlighting and mermaid.
import { h, state, slug } from './util.js';

const DOC_NAMES = ['README', 'GLOSSARY', 'TIPS', 'KEYWORD_INDEX'];

/** Map a playbook-relative path (+ link text) to an in-app route, or null. */
export function routeFor(relPath, text = '') {
  const [p, hash = ''] = relPath.split('#');
  let m;
  const qid = /^(Q\d{2}\.\d{2})$/.exec(text.trim());
  if ((m = /^chapters\/(\d{2})_[^/]+\/?(README\.md)?$/.exec(p))) return hash ? `#/chapter/${m[1]}/lesson/#${hash}` : `#/chapter/${m[1]}`;
  if ((m = /^chapters\/(\d{2})_[^/]+\/queries\.sql$/.exec(p))) return `#/chapter/${m[1]}/queries${qid ? '/' + qid[1] : ''}`;
  if ((m = /^chapters\/(\d{2})_[^/]+\/(exercises|solutions)\.sql$/.exec(p))) return `#/chapter/${m[1]}/practice`;
  if ((m = /^([A-Z_]+)\.md$/.exec(p)) && DOC_NAMES.includes(m[1])) return m[1] === 'README' ? '#/doc/README' : `#/doc/${m[1]}${hash ? '/#' + hash : ''}`;
  if (/\.md$/.test(p)) return `#/md/${p}`;
  if (/\.(sql|csv|yml|sh)$/.test(p)) return `#/file/${p}`;
  return null;
}

function resolvePath(base, href) {
  const u = new URL(href, 'http://pb/' + base);
  return decodeURIComponent(u.pathname.slice(1)) + (u.hash || '');
}

let mermaidLoading = null;
function loadMermaid() {
  if (!mermaidLoading) {
    mermaidLoading = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = '/vendor/mermaid/mermaid.min.js';
      s.onload = () => resolve(window.mermaid);
      s.onerror = reject;
      document.head.append(s);
    });
  }
  return mermaidLoading;
}

export async function renderMermaid(root) {
  const nodes = [...root.querySelectorAll('.mermaid')];
  if (!nodes.length) return;
  try {
    const mermaid = await loadMermaid();
    mermaid.initialize({ startOnLoad: false, theme: state.theme === 'dark' ? 'dark' : 'default', securityLevel: 'strict', er: { useMaxWidth: true } });
    await mermaid.run({ nodes });
  } catch (e) {
    console.warn('mermaid failed', e);
  }
}

/**
 * @param md       markdown text
 * @param basePath path of the markdown file relative to the playbook root (for link resolution)
 * @param onTry    callback(sql) for the "Try it" button on SQL code blocks
 */
export function renderMarkdown(md, basePath, { onTry } = {}) {
  const root = h('div.md', { html: window.marked.parse(md, { gfm: true }) });

  // heading anchors
  for (const hd of root.querySelectorAll('h1,h2,h3,h4')) hd.id = slug(hd.textContent);

  // links
  for (const a of root.querySelectorAll('a[href]')) {
    const href = a.getAttribute('href');
    if (/^(https?:|mailto:)/.test(href)) { a.target = '_blank'; a.rel = 'noopener'; continue; }
    if (href.startsWith('#')) { a.dataset.anchor = href.slice(1); a.setAttribute('href', 'javascript:void 0'); continue; }
    const route = routeFor(resolvePath(basePath, href), a.textContent);
    if (route) {
      a.setAttribute('href', route);
      if (/^Q\d{2}\.\d{2}$/.test(a.textContent.trim())) a.classList.add('qref');
    } else {
      a.replaceWith(h('span', a.textContent));
    }
  }
  root.addEventListener('click', (ev) => {
    const a = ev.target.closest('a[data-anchor]');
    if (!a) return;
    ev.preventDefault();
    root.querySelector(`#${CSS.escape(a.dataset.anchor)}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });

  // plain-text query ids → links (skip code/pre/links)
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) => (n.parentElement.closest('a,code,pre') ? NodeFilter.FILTER_REJECT : /\bQ\d{2}\.\d{2}\b/.test(n.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
  });
  const texts = [];
  while (walker.nextNode()) texts.push(walker.currentNode);
  for (const t of texts) {
    const frag = document.createDocumentFragment();
    let last = 0;
    t.nodeValue.replace(/\bQ(\d{2})\.(\d{2})\b/g, (m, ch, n, idx) => {
      frag.append(t.nodeValue.slice(last, idx));
      frag.append(h('a.qref', { href: `#/chapter/${ch}/queries/${m}` }, m));
      last = idx + m.length;
      return m;
    });
    frag.append(t.nodeValue.slice(last));
    t.replaceWith(frag);
  }

  // code blocks: mermaid diagrams, SQL highlighting + "try it"
  for (const code of root.querySelectorAll('pre > code')) {
    const pre = code.parentElement;
    const lang = (code.className.match(/language-(\w+)/) || [])[1];
    if (lang === 'mermaid') {
      pre.replaceWith(h('div.mermaid', code.textContent));
      continue;
    }
    if (lang === 'sql' || (!lang && /\b(SELECT|INSERT|UPDATE|CREATE|ALTER|BEGIN)\b/.test(code.textContent))) {
      const text = code.textContent;
      code.textContent = '';
      code.classList.add('cm-s-' + (state.theme === 'dark' ? 'material-darker' : 'eclipse'));
      window.CodeMirror.runMode(text, 'text/x-pgsql', code);
      if (onTry && /\b(SELECT|WITH|EXPLAIN|SHOW|VALUES)\b/i.test(text)) {
        pre.append(h('button.btn.btn-small.try-btn', { onclick: () => onTry(text) }, '▶ Try in scratchpad'));
      }
    }
  }
  return root;
}
