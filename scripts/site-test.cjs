// Headless browser check of docs/index.html (Playwright + Chromium headless shell).
// Run: scripts/site-test.sh
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const url = 'file://' + path.join(root, 'docs/index.html');
const langs = ['en', 'ko', 'ja', 'zh', 'es', 'de', 'fr'];
const installCmd = 'brew install --cask namekun/tap/nunsseop';
const upgradeCmd = 'brew update && brew upgrade --cask nunsseop';
const tourImages = ['home.png', 'tab-ai.png', 'tab-search.png', 'shelf.png', 'tab-timer.png', 'tab-tools.png', 'tab-system.png', 'tab-emoji.png'];
const enTourTitles = ['Home', 'AI usage', 'Search', 'Shelf', 'Timer', 'Tools', 'System', 'Emoji'];
// Titles that really are the same word in that language (loanwords); every other title and every text must differ from English.
const sameAsEnglish = new Set(['de:Timer', 'de:System', 'es:Emoji', 'de:Emoji', 'fr:Emoji']);
const failures = [];
const check = (ok, msg) => { if (!ok) failures.push(msg); };
const pickLang = async (page, lang) => {
  await page.click('.lang-btn');
  await page.click(`[data-set="${lang}"]`);
};

(async () => {
  const browser = await chromium.launch();

  // Desktop: errors, images, every language.
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'en-US' });
  page.on('pageerror', e => failures.push('page error: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') failures.push('console error: ' + m.text()); });
  await page.goto(url);
  await page.waitForLoadState('load');

  // Lazy images only load near the viewport, so load them all before checking.
  const broken = await page.$$eval('img', imgs => Promise.all(imgs.map(i => {
    i.loading = 'eager';
    return i.decode().then(() => null, () => i.getAttribute('src'));
  })).then(r => r.filter(Boolean)));
  check(broken.length === 0, 'broken images: ' + broken.join(', '));

  for (const lang of langs) {
    await pickLang(page, lang);
    const r = await page.evaluate(([lang, langs]) => {
      const visible = el => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
      const own = [...document.querySelectorAll('.' + lang)].filter(visible);
      const others = langs.filter(l => l !== lang)
        .flatMap(l => [...document.querySelectorAll('.' + l)]).filter(visible);
      return {
        own: own.length,
        empty: own.filter(el => !el.textContent.trim() && !el.querySelector('img')).length,
        leaked: others.length,
        htmlLang: document.documentElement.lang,
      };
    }, [lang, langs]);
    check(r.own > 0, `${lang}: no visible text`);
    check(r.empty === 0, `${lang}: ${r.empty} empty visible elements`);
    check(r.leaked === 0, `${lang}: ${r.leaked} elements of other languages visible`);
    check(r.htmlLang.startsWith(lang), `${lang}: <html lang> is ${r.htmlLang}`);
  }

  // Version badge: the plist is the source of truth, and release.sh's sed needs the badge to match it exactly.
  const plist = fs.readFileSync(path.join(root, 'Resources/Info.plist'), 'utf8');
  const plistValue = key => (plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`)) || [])[1];
  const version = plistValue('CFBundleShortVersionString');
  check(/^\d+\.\d+\.\d+$/.test(version || ''), `Info.plist version is ${version}`);
  check(/^[1-9]\d*$/.test(plistValue('CFBundleVersion') || ''), `Info.plist build number is ${plistValue('CFBundleVersion')}`);
  const badge = await page.$$eval('.eyebrow b', bs => bs.map(b => ({ text: b.textContent, href: b.closest('a') && b.closest('a').getAttribute('href') })));
  check(badge.length === 1, `expected one version badge, found ${badge.length}`);
  check(badge[0] && badge[0].text === 'v' + version, `version badge is ${badge[0] && badge[0].text}, Info.plist says v${version}`);
  check(badge[0] && badge[0].href === 'https://github.com/namekun/Nunsseop/releases/latest', `version badge links to ${badge[0] && badge[0].href}`);

  // Every in-page link lands on an element.
  const dead = await page.$$eval('a[href^="#"]', as => as.map(a => a.getAttribute('href')).filter(h => !document.getElementById(h.slice(1))));
  check(dead.length === 0, 'anchors without a target: ' + dead.join(', '));

  // Meta and Open Graph tags, and the preview image they point at.
  const meta = await page.evaluate(() => {
    const get = sel => { const el = document.querySelector(sel); return el ? el.getAttribute('content') : null; };
    return {
      title: document.title, description: get('meta[name="description"]'),
      ogTitle: get('meta[property="og:title"]'), ogDescription: get('meta[property="og:description"]'),
      ogUrl: get('meta[property="og:url"]'), ogImage: get('meta[property="og:image"]'),
      ogWidth: get('meta[property="og:image:width"]'), ogHeight: get('meta[property="og:image:height"]'),
      ogAlt: get('meta[property="og:image:alt"]'), twCard: get('meta[name="twitter:card"]'), twImage: get('meta[name="twitter:image"]'),
    };
  });
  for (const k of ['title', 'description', 'ogTitle', 'ogDescription', 'ogUrl', 'ogImage', 'ogAlt', 'twCard']) {
    check(meta[k] && meta[k].trim(), `meta ${k} is missing or empty`);
  }
  check((meta.description || '').length <= 200, `meta description is ${(meta.description || '').length} characters`);
  check(meta.twCard === 'summary_large_image', `twitter:card is ${meta.twCard}`);
  check(meta.ogUrl === 'https://namekun.github.io/Nunsseop/', `og:url is ${meta.ogUrl}`);
  check(meta.twImage === meta.ogImage, `twitter:image ${meta.twImage} differs from og:image ${meta.ogImage}`);
  const og = /^https:\/\/namekun\.github\.io\/Nunsseop\/(images\/og\.png)(\?v=\d+)?$/.exec(meta.ogImage || '');
  check(og, `og:image is ${meta.ogImage}`);
  if (og) {
    const png = fs.readFileSync(path.join(root, 'docs', og[1]));
    check(png.subarray(1, 4).toString() === 'PNG', 'docs/images/og.png is not a PNG');
    const size = `${png.readUInt32BE(16)}x${png.readUInt32BE(20)}`;
    check(size === '1200x630' && `${meta.ogWidth}x${meta.ogHeight}` === size, `og.png is ${size}, og:image:width/height say ${meta.ogWidth}x${meta.ogHeight}, expected 1200x630`);
  }

  // Links leave the page only for known places.
  const hrefs = await page.$$eval('a[href]', as => as.map(a => a.getAttribute('href')).filter(h => !h.startsWith('#')));
  const okLinks = new Set(['https://brew.sh', 'https://github.com/namekun/Nunsseop', 'https://github.com/namekun/Nunsseop/releases',
    'https://github.com/namekun/Nunsseop/releases/latest', 'https://github.com/namekun/homebrew-tap']);
  check(hrefs.every(h => okLinks.has(h)), 'unexpected links: ' + [...new Set(hrefs.filter(h => !okLinks.has(h)))].join(', '));
  for (const h of okLinks) check(hrefs.includes(h), 'link no longer on the page: ' + h);

  // Every translated block has all seven languages: among the children of one parent, each language appears as often as the others.
  const uneven = await page.evaluate(langs => {
    const out = [];
    for (const parent of document.querySelectorAll('body, body *')) {
      const counts = langs.map(l => [...parent.children].filter(c => c.classList.contains(l)).length);
      if (counts.some(n => n) && counts.some(n => n !== counts[0])) {
        out.push(`${parent.tagName.toLowerCase()}${parent.id ? '#' + parent.id : parent.className ? '.' + String(parent.className).split(' ')[0] : ''} ${counts.join('/')}`);
      }
    }
    return out;
  }, langs);
  check(uneven.length === 0, 'blocks that miss a language (en/ko/ja/zh/es/de/fr counts): ' + uneven.join('; '));

  // Tour: every item in every language shows its own text and image.
  const tourBtns = await page.$$eval('#tourList .tour-btn', bs => bs.length);
  check(tourBtns === tourImages.length, `tour has ${tourBtns} items, expected ${tourImages.length}`);
  for (const f of tourImages) check(fs.existsSync(path.join(root, 'docs/images', f)), 'tour image missing: docs/images/' + f);
  const enTour = [];
  for (const lang of langs) {
    await pickLang(page, lang);
    for (let i = 0; i < tourImages.length; i++) {
      await page.click(`#tourList .tour-btn:nth-child(${i + 1})`);
      const t = await page.evaluate(([lang, i]) => {
        const btns = [...document.querySelectorAll('#tourList .tour-btn')];
        return {
          title: document.getElementById('tourTitle').textContent,
          text: document.getElementById('tourText').textContent.trim(),
          label: btns[i].querySelector('.lbl .' + lang).textContent,
          pressed: btns.map(b => b.getAttribute('aria-pressed')),
          imgs: [...document.querySelectorAll('#tourScreen img.on')].map(im => ({ src: im.getAttribute('src'), width: im.naturalWidth })),
        };
      }, [lang, i]);
      const where = `tour ${lang} item ${i + 1}`;
      check(t.title && t.title !== 'undefined', `${where}: empty title`);
      check(t.title === t.label, `${where}: title "${t.title}" differs from button label "${t.label}"`);
      check(t.text && t.text !== 'undefined', `${where}: empty text`);
      if (lang === 'en') enTour[i] = { title: t.title, text: t.text };
      else if (enTour[i]) {
        check(t.title !== enTour[i].title || sameAsEnglish.has(`${lang}:${t.title}`), `${where}: title is still the English "${t.title}"`);
        check(t.text !== enTour[i].text, `${where}: text is still the English text`);
      }
      if (lang === 'en') check(t.title === enTourTitles[i], `${where}: title is "${t.title}", expected "${enTourTitles[i]}"`);
      check(t.pressed.join() === tourImages.map((_, j) => String(j === i)).join(), `${where}: aria-pressed is ${t.pressed.join()}`);
      check(t.imgs.length === 1 && t.imgs[0].src === 'images/' + tourImages[i] && t.imgs[0].width > 0,
        `${where}: shown image is ${JSON.stringify(t.imgs)}, expected images/${tourImages[i]}`);
    }
  }

  // Choice survives a reload.
  await pickLang(page, 'de');
  await page.reload();
  check(await page.getAttribute('body', 'data-lang') === 'de', 'language choice not kept after reload');

  // First visit follows the browser language.
  for (const [locale, want] of [['ko-KR', 'ko'], ['ja-JP', 'ja'], ['zh-CN', 'zh'], ['fr-FR', 'fr'], ['it-IT', 'en']]) {
    const ctx = await browser.newContext({ locale });
    const p = await ctx.newPage();
    await p.goto(url);
    const got = await p.getAttribute('body', 'data-lang');
    check(got === want, `locale ${locale}: expected ${want}, got ${got}`);
    await ctx.close();
  }

  // Copy buttons put the command the page shows on the clipboard. A fake clock stands in for the 1.4 s label reset.
  const cctx = await browser.newContext({ locale: 'en-US', permissions: ['clipboard-read', 'clipboard-write'] });
  const cp = await cctx.newPage();
  cp.on('pageerror', e => failures.push('copy page error: ' + e.message));
  cp.on('console', m => { if (m.type() === 'error') failures.push('copy page console error: ' + m.text()); });
  await cp.clock.install();
  await cp.goto(url);
  const copies = await cp.$$eval('[data-copy]', bs => bs.map(b => ({
    copy: b.getAttribute('data-copy'),
    shown: (b.parentElement.querySelector('code, pre') || {}).textContent,
  })));
  check(copies.length === 3, `expected 3 copy buttons, found ${copies.length}`);
  copies.forEach((c, i) => check(c.shown && c.shown.trim().split('\n').join(' && ') === c.copy, `copy button ${i}: shows "${c.shown}" but copies "${c.copy}"`));
  check(copies.filter(c => c.copy === installCmd).length === 2, `install command is on ${copies.filter(c => c.copy === installCmd).length} copy buttons, expected 2`);
  const copyBtns = await cp.$$('[data-copy]');
  for (let i = 0; i < copyBtns.length; i++) {
    // The source panel is hidden until its tab is selected.
    if (copies[i].copy.startsWith('git clone')) await cp.click('[data-tab="src"]');
    await copyBtns[i].scrollIntoViewIfNeeded();
    const label = async () => (await copyBtns[i].innerText()).trim();
    const before = await label();
    check(before === 'Copy', `copy button ${i}: label is "${before}" before click`);
    await copyBtns[i].click();
    const clip = await cp.evaluate(() => navigator.clipboard.readText());
    check(clip === copies[i].copy, `copy button ${i}: clipboard has "${clip}", expected "${copies[i].copy}"`);
    check(await label() === 'Copied', `copy button ${i}: label is not Copied after click`);
    await cp.clock.runFor(1500);
    check(await label() === 'Copy', `copy button ${i}: label did not return to Copy`);
  }
  await cctx.close();

  // The commands are the same everywhere they are written down.
  for (const f of ['README.md', 'README.ko.md', 'README.ja.md', 'README.zh-Hans.md', 'README.es.md', 'README.de.md', 'README.fr.md']) {
    const text = fs.readFileSync(path.join(root, f), 'utf8');
    check(text.includes(installCmd), `${f} does not contain "${installCmd}"`);
    check(text.includes(upgradeCmd), `${f} does not contain "${upgradeCmd}"`);
  }
  const html = fs.readFileSync(path.join(root, 'docs/index.html'), 'utf8');
  const upgradeOnSite = html.split(upgradeCmd.replace('&&', '&amp;&amp;')).length - 1;
  check(upgradeOnSite === langs.length, `site shows the upgrade command ${upgradeOnSite} times, expected ${langs.length}`);
  const swift = fs.readFileSync(path.join(root, 'Sources/Nunsseop/UpdateChecker.swift'), 'utf8');
  check(swift.includes(`"${upgradeCmd}"`), 'UpdateChecker no longer uses the upgrade command the site documents');
  check(swift.includes('brew update && brew install --cask --force namekun/tap/nunsseop'), 'UpdateChecker reinstall command drifted from the tap name');

  // Mobile: nothing wider than the screen.
  const mobile = await browser.newPage({ viewport: { width: 375, height: 812 } });
  await mobile.goto(url);
  // Decorations may extend past the edge; what matters is that the page can't scroll sideways.
  const scrollX = await mobile.evaluate(() => { window.scrollTo(1000, 0); return window.scrollX; });
  check(scrollX === 0, `mobile: page scrolls sideways by ${scrollX}px`);

  await browser.close();
  if (failures.length) {
    console.error(failures.map(f => 'FAIL ' + f).join('\n'));
    process.exit(1);
  }
  console.log(`site OK: ${langs.length} languages, images, version badge, meta tags, anchors, tour, copy buttons, persistence, locale detection, mobile width`);
})().catch(e => { console.error(e); process.exit(1); });
