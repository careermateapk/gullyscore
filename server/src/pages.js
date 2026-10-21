// Web pages from assets/content/pages.json (the same text the app shows):
// home, privacy policy, terms, about us and the blog.
import content from '../../assets/content/pages.json' with { type: 'json' };
import { esc, html } from './util.js';

const CSS = `
:root{--bg:#070F1E;--s1:#0E1B30;--ln:#1C2D47;--tx:#F2F5FA;--t2:#A9B6C9;--gd:#FFC94A;--ok:#2BD38A}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans Devanagari",sans-serif}
main{max-width:720px;margin:0 auto;padding:20px 16px 48px}a{color:var(--gd)}
header{display:flex;align-items:center;gap:10px;flex-wrap:wrap;justify-content:space-between}
.brand{font-weight:800;font-size:20px;text-decoration:none;color:var(--tx)}
nav a{margin-left:14px;font-weight:700;font-size:14px;text-decoration:none}
h1{font-size:28px;line-height:1.25;margin:24px 0 4px}h2{font-size:19px;margin:28px 0 8px}
.t2{color:var(--t2)}.box{background:linear-gradient(165deg,#17325A,#0E1B30 70%);border:1px solid #234071;border-radius:20px;padding:16px 18px;margin-top:16px}
.box p{margin:8px 0;font-weight:600}.box p:before{content:"✓  ";color:var(--ok);font-weight:900}
ul{padding-left:20px}li{margin:6px 0;color:var(--t2)}p{color:var(--t2)}
.card{display:block;background:var(--s1);border:1px solid var(--ln);border-radius:18px;padding:16px;margin-top:12px;text-decoration:none;color:var(--tx)}
.card b{font-size:18px}.lang{font-size:14px}
footer{margin-top:40px;color:var(--t2);font-size:13px;text-align:center}
`;

function page(title, body, lang = 'en') {
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · GullyScore</title><style>${CSS}</style></head><body><main>
<header><a class="brand" href="/">🏏 GullyScore</a><nav><a href="/blog">Blog</a><a href="/about">About</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a></nav></header>
${body}
<footer>GullyScore · Made in India</footer></main></body></html>`;
}

function infoPage(kind, lang) {
  const both = content.pages[kind];
  const c = both[lang] || both.en;
  const other = lang === 'hi' ? 'en' : 'hi';
  const items = (lines) => (lines.length === 1 ? `<p>${esc(lines[0])}</p>` : `<ul>${lines.map((l) => `<li>${esc(l)}</li>`).join('')}</ul>`);
  return page(
    c.title,
    `<h1>${esc(c.title)}</h1>
${kind === 'about' ? '' : `<div class="t2">Last updated ${esc(content.updated)}</div>`}
<a class="lang" href="?lang=${other}">${other === 'hi' ? 'हिंदी में पढ़ें' : 'Read in English'}</a>
<div class="box">${c.short.map((s) => `<p>${esc(s)}</p>`).join('')}</div>
${c.sections.map(([h, lines], i) => `<h2>${kind === 'about' ? '' : `${i + 1}. `}${esc(h)}</h2>${items(lines)}`).join('\n')}
${content.contact ? `<h2>Contact</h2><p>${esc(content.contact)}</p>` : ''}`,
    lang,
  );
}

export function contentRoutes(p, method, url) {
  if (method !== 'GET') return null;
  const lang = url.searchParams.get('lang') === 'hi' ? 'hi' : 'en';
  if (p === '/' ) {
    return html(
      page(
        'Cricket scoring for every gully',
        `<h1>Score every ball. Share it live.</h1><p>GullyScore is a free cricket scoring app for gully, school and local tournament cricket. Made in India.</p>
<a class="card" href="/blog"><b>Blog</b><div class="t2">Tips and updates</div></a>
<a class="card" href="/about"><b>About us</b></a>`,
      ),
    );
  }
  if (p === '/privacy' || p === '/terms' || p === '/about') return html(infoPage(p.slice(1), lang));
  if (p === '/blog') {
    return html(
      page(
        'Blog',
        `<h1>Blog</h1><p>Tips for scoring and running local cricket, and what is new in GullyScore.</p>
${content.blog.map((b) => `<a class="card" href="/blog/${esc(b.slug)}"><b>${esc(b.title)}</b><div class="t2">${esc(b.date)}</div><p>${esc(b.summary)}</p></a>`).join('')}`,
      ),
    );
  }
  const m = /^\/blog\/([a-z0-9-]+)$/.exec(p);
  if (m) {
    const b = content.blog.find((x) => x.slug === m[1]);
    if (!b) return null;
    return html(page(b.title, `<h1>${esc(b.title)}</h1><div class="t2">${esc(b.date)}</div><p>${esc(b.summary)}</p><ol>${b.body.map((l) => `<li>${esc(l)}</li>`).join('')}</ol><p><a href="/blog">← All posts</a></p>`));
  }
  return null;
}
