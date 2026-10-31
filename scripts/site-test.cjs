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
// A panel slides in when its tab is chosen; a click during that can land beside the button it aims at.
const settledPanel = page => page.waitForFunction(() => !document.querySelector('.panel.active').getAnimations({ subtree: true })
  .some(a => a.playState === 'running'));
// The page waits on its web font, which can take longer than a navigation is given. The document is what the checks
// need; the fonts get another minute, without failing anything when they take longer.
const openPage = async (page) => {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('load', { timeout: 60000 }).catch(() => {});
};
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
  await openPage(page);
  
  // An automated browser that never scrolls (a full-page capture) still gets every block.
  check(await page.evaluate(() => document.querySelectorAll('.reveal-pre').length) === 0, 'blocks hidden in an automated browser');

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
    'https://github.com/namekun/Nunsseop/releases/latest', 'https://github.com/namekun/homebrew-tap', 'https://github.com/namekun/Nunsseop/releases/latest/download/Nunsseop.dmg']);
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
    await openPage(p);
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
  await openPage(cp);
  const copies = await cp.$$eval('[data-copy]', bs => bs.map(b => ({
    copy: b.getAttribute('data-copy'),
    shown: (b.parentElement.querySelector('code, pre') || {}).textContent,
  })));
  check(copies.length === 3, `expected 3 copy buttons, found ${copies.length}`);
  copies.forEach((c, i) => check(c.shown && c.shown.trim().split('\n').join(' && ') === c.copy, `copy button ${i}: shows "${c.shown}" but copies "${c.copy}"`));
  check(copies.filter(c => c.copy === installCmd).length === 2, `install command is on ${copies.filter(c => c.copy === installCmd).length} copy buttons, expected 2`);
  const copyBtns = await cp.$$('[data-copy]');
  for (let i = 0; i < copyBtns.length; i++) {
    // A panel other than the first is hidden until its tab is selected.
    const tab = await copyBtns[i].evaluate(b => { const panel = b.closest('.panel'); return panel && panel.dataset.panel; });
    if (tab) { await cp.click(`[data-tab="${tab}"]`); await settledPanel(cp); }
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
    // A second click before the label resets must not keep "Copied" for good.
    // Reading the clipboard back waits for each write to finish before the clock moves.
    await copyBtns[i].click();
    await cp.evaluate(() => navigator.clipboard.readText());
    await cp.clock.runFor(500);
    await copyBtns[i].click();
    await cp.evaluate(() => navigator.clipboard.readText());
    await cp.clock.runFor(1500);
    check(await label() === 'Copy', `copy button ${i}: label stuck on "${await label()}" after two quick clicks`);
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
  // The DMG the site offers is the one release.sh uploads under a fixed name; the app downloads it by version.
  check(fs.readFileSync(path.join(root, 'scripts/release.sh'), 'utf8').includes('build/Nunsseop.dmg'), 'release.sh no longer uploads Nunsseop.dmg, which the download button links to');
  // Sparkle: the feed every copy from the DMG asks is the one release.sh uploads, signed with the key Info.plist trusts.
  check(plistValue('SUFeedURL') === 'https://github.com/namekun/Nunsseop/releases/latest/download/appcast.xml', `SUFeedURL is ${plistValue('SUFeedURL')}`);
  check(Buffer.from(plistValue('SUPublicEDKey') || '', 'base64').length === 32, 'SUPublicEDKey is not a 32 byte key');
  check(!plist.includes('NunsseopUpdaterAnywhere'), 'the test-only NunsseopUpdaterAnywhere key is in Info.plist');
  check(fs.readFileSync(path.join(root, 'scripts/release.sh'), 'utf8').includes('build/appcast.xml'), 'release.sh no longer uploads the appcast.xml SUFeedURL points to');
  const sparkle = /sparkle-project\/Sparkle", exact: "(\d+)\.(\d+)\.(\d+)"/.exec(fs.readFileSync(path.join(root, 'Package.swift'), 'utf8'));
  check(sparkle && [2, 9, 6].reduce((cmp, min, i) => cmp || Math.sign(+sparkle[i + 1] - min), 0) >= 0, 'Sparkle must be pinned at 2.9.6 or later, the oldest without known advisories');
  check(swift.includes('releases/download/v\\(version)/Nunsseop-\\(version).dmg'), 'UpdateChecker downloads a DMG name release.sh no longer uses');

  // Mobile: nothing wider than the screen.
  const mobile = await browser.newPage({ viewport: { width: 375, height: 812 } });
  await openPage(mobile);
  // Decorations may extend past the edge; what matters is that the page can't scroll sideways.
  const scrollX = await mobile.evaluate(() => { window.scrollTo(1000, 0); return window.scrollX; });
  check(scrollX === 0, `mobile: page scrolls sideways by ${scrollX}px`);

  // No text runs out of its box into the next column (a Korean list joined by "·" did, as one unbreakable word).
  for (const [p, name] of [[page, 'desktop'], [mobile, 'mobile']]) {
    for (const lang of langs) {
      await pickLang(p, lang);
      const wide = await p.evaluate(() => [...document.querySelectorAll('main p, main h2, main h3, main li')]
        .filter(el => el.getClientRects().length)
        .map(el => {
          const box = el.parentElement, s = getComputedStyle(box);
          const edge = box.getBoundingClientRect().right - parseFloat(s.paddingRight) - parseFloat(s.borderRightWidth);
          return [Math.round(el.getBoundingClientRect().right - edge), el.textContent.trim().slice(0, 40)];
        })
        .filter(([over]) => over > 1)
        .map(([over, text]) => `+${over}px "${text}"`));
      check(wide.length === 0, `${name} ${lang}: text wider than its box: ${wide.join('; ')}`);
    }
  }

  // Spacing sits on an 8-point grid: every margin, padding and gap that shows is a multiple of 8. Margins that centre a box are the exception.
  for (const [p, name] of [[page, 'desktop'], [mobile, 'mobile']]) {
    for (const lang of langs) {
      await pickLang(p, lang);
      const off = await p.evaluate(() => {
        const props = ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'marginTop', 'marginBottom', 'rowGap', 'columnGap'];
        const out = new Set();
        for (const el of document.querySelectorAll('body, body *')) {
          if (!el.getClientRects().length || el.closest('svg') || el.classList.contains('sr-only')) continue;
          const cs = getComputedStyle(el);
          const sides = cs.marginLeft === cs.marginRight ? [] : ['marginLeft', 'marginRight'];
          for (const k of [...props, ...sides]) {
            const v = parseFloat(cs[k]);
            if (Number.isFinite(v) && v % 8) out.add(`${el.tagName.toLowerCase()}.${String(el.className).split(' ')[0]} ${k} ${cs[k]}`);
          }
        }
        return [...out];
      });
      check(off.length === 0, `${name} ${lang}: spacing off the 8-point grid: ${off.join('; ')}`);
    }
  }

  // Every Copy button (hero, Homebrew tab, Source tab): "Copied" only when the clipboard write really succeeded.
  const copied = { en: 'Copied', ko: '복사됨', ja: 'コピーしました', zh: '已复制', es: 'Copiado', de: 'Kopiert', fr: 'Copié' };
  const copyFailed = { en: 'Copy failed', ko: '복사 실패', ja: 'コピーできませんでした', zh: '复制失败', es: 'No se pudo copiar', de: 'Kopieren fehlgeschlagen', fr: 'Échec de la copie' };
  const buttonCount = await page.locator('[data-copy]').count();
  check(buttonCount === 3, `expected 3 copy buttons, found ${buttonCount}`);
  const clipboards = {
    ok: 'Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => Promise.resolve() } })',
    rejected: 'Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => Promise.reject(new Error("denied")) } })',
    throwing: 'Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => { throw new Error("denied"); } } })',
    missing: 'Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined })',
  };
  for (const [kind, script] of Object.entries(clipboards)) {
    for (const lang of langs) {
      for (let i = 0; i < buttonCount; i++) {
        const ctx = await browser.newContext({ locale: 'en-US' });
        const p = await ctx.newPage();
        const errors = [];
        p.on('pageerror', e => errors.push(e.message));
        await p.addInitScript(script);
        await p.addInitScript(`localStorage.setItem('nunsseop-lang', '${lang}')`);
        await openPage(p);
        const btn = p.locator('[data-copy]').nth(i);
        const tab = await btn.evaluate(b => { const panel = b.closest('.panel'); return panel && panel.dataset.panel; });
        if (tab) { await p.click(`.tabs button[data-tab="${tab}"]`); await settledPanel(p); }
        const where = `${lang}: copy button ${i}`;
        const shown = await btn.evaluate(b => (b.parentNode.querySelector('pre, code').textContent || '').replace(/\s+/g, ' ').trim());
        const idle = await btn.innerHTML();
        await btn.click();
        const label = (await btn.textContent()).trim();
        if (kind === 'ok') {
          check(label === copied[lang], `${where} said "${label}" after a successful write`);
        } else {
          check(label !== copied[lang], `${where} said "${label}" although the clipboard write failed (${kind})`);
          check(label === copyFailed[lang], `${where} said "${label}" after a failed write (${kind}), expected "${copyFailed[lang]}"`);
          const selected = await p.evaluate(() => String(getSelection()).replace(/\s+/g, ' ').trim());
          check(selected === shown, `${where}: failed copy (${kind}) left "${selected}" selected, expected "${shown}"`);
        }
        await p.waitForFunction(([n, html]) => document.querySelectorAll('[data-copy]')[n].innerHTML === html, [i, idle], { timeout: 3000 })
          .catch(() => failures.push(`${where} did not go back to its label (${kind})`));
        check(errors.length === 0, `${where} (${kind}) raised: ${errors.join('; ')}`);
        await ctx.close();
      }
    }
  }

  // Motion (Transitions.dev). Content never depends on it: state changes at once, motion is layered on top.
  const clipOk = 'Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => Promise.resolve() } })';
  const clipDenied = 'Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => Promise.reject(new Error("denied")) } })';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const menuOpen = p => p.evaluate(() => document.getElementById('lang').classList.contains('open'));
  const scrollThrough = async p => {
    const h = await p.evaluate(() => document.documentElement.scrollHeight);
    for (let y = 0; y < h; y += 400) { await p.evaluate(y => window.scrollTo(0, y), y); await sleep(40); }
    await p.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  };

  // Reduce Motion: every block is there without scrolling, nothing runs, nothing is transformed or blurred.
  {
    const rctx = await browser.newContext({ locale: 'en-US', reducedMotion: 'reduce', viewport: { width: 1280, height: 800 } });
    await rctx.addInitScript(clipOk);
    const rp = await rctx.newPage();
    rp.on('pageerror', e => failures.push('reduced-motion page error: ' + e.message));
    rp.on('console', m => { if (m.type() === 'error') failures.push('reduced-motion console error: ' + m.text()); });
    await openPage(rp);
        await sleep(300);
    const r = await rp.evaluate(() => {
      const shown = sel => [...document.querySelectorAll(sel)].filter(el => el.getClientRects().length);
      const moving = shown('.reveal, .nn-word, .hero .lead, .hero .cta, .copy > span, #tourTitle, #tourText')
        .filter(el => { const cs = getComputedStyle(el); return cs.transform !== 'none' || cs.filter !== 'none' || cs.opacity !== '1'; })
        .map(el => el.className || el.id || el.tagName);
      return {
        reveals: document.querySelectorAll('.reveal').length,
        pending: document.querySelectorAll('.reveal-pre').length,
        moving,
        menuTransform: getComputedStyle(document.querySelector('.lang-menu')).transform,
        blurredShots: [...document.querySelectorAll('.tour-screen img')].filter(i => getComputedStyle(i).filter !== 'none').length,
        running: document.getAnimations().filter(a => a.playState === 'running').length,
      };
    });
    check(r.reveals > 0, 'reduced motion: no .reveal blocks found');
    check(r.pending === 0, `reduced motion: ${r.pending} blocks are still waiting to be revealed`);
    check(r.moving.length === 0, 'reduced motion: still transformed, blurred or faded: ' + r.moving.join(', '));
    check(r.menuTransform === 'none', 'reduced motion: language menu is transformed: ' + r.menuTransform);
    check(r.blurredShots === 0, 'reduced motion: tour screens are blurred');
    check(r.running === 0, `reduced motion: ${r.running} animations are running`);
    // The language menu still works, and closes at once.
    await rp.click('.lang-btn');
    check(await rp.getAttribute('.lang-btn', 'aria-expanded') === 'true', 'reduced motion: language menu did not open');
    check(await rp.locator('[data-set="ko"]').isVisible(), 'reduced motion: language options not visible');
    await rp.click('[data-set="ko"]');
    check(await rp.getAttribute('body', 'data-lang') === 'ko', 'reduced motion: language did not change');
    check(!(await rp.locator('[data-set="ko"]').isVisible()), 'reduced motion: language menu stayed visible after choosing');
    check(await rp.locator('.lang-menu.is-closing').count() === 0, 'reduced motion: language menu is animating shut');
    await rp.click('.lang-btn');
    await rp.click('[data-set="en"]');
    // Copy feedback is instant and still.
    const cb = rp.locator('[data-copy]').first();
    await cb.click();
    check((await cb.innerText()).trim() === 'Copied', 'reduced motion: copy did not say Copied');
    check(await cb.getAttribute('data-prev') === null, 'reduced motion: copy button keeps a ghost label');
    check(await cb.evaluate(b => b.getAnimations({ subtree: true }).length) === 0, 'reduced motion: copy button animates');
    // A FAQ answer shows when opened.
    await rp.locator('.faq summary').first().click();
    check(await rp.locator('.faq details').first().evaluate(d => [...d.querySelectorAll('.a')].some(a => a.getClientRects().length)), 'reduced motion: FAQ answer not shown');
    await rp.setViewportSize({ width: 390, height: 844 });
    const sx = await rp.evaluate(() => { window.scrollTo(1000, 0); return window.scrollX; });
    check(sx === 0, `reduced motion, mobile: page scrolls sideways by ${sx}px`);
    await rctx.close();
  }

  // With motion: blocks below the fold wait, then arrive as scrolled to, without moving anything else on the page.
  {
    const mctx = await browser.newContext({ locale: 'en-US', viewport: { width: 1280, height: 800 } });
    await mctx.addInitScript(clipOk);
    // Automated browsers get everything at once; this context stands in for a visitor.
    await mctx.addInitScript(() => Object.defineProperty(Navigator.prototype, 'webdriver', { get: () => false }));
    const mp = await mctx.newPage();
    mp.on('pageerror', e => failures.push('motion page error: ' + e.message));
    mp.on('console', m => { if (m.type() === 'error') failures.push('motion console error: ' + m.text()); });
    await openPage(mp);
        const pend = await mp.evaluate(() => {
      const waiting = [...document.querySelectorAll('.reveal-pre')];
      const before = waiting.map(el => [el.offsetTop, el.offsetHeight]);
      waiting.forEach(el => el.classList.remove('reveal-pre'));
      const moved = waiting.filter((el, i) => el.offsetTop !== before[i][0] || el.offsetHeight !== before[i][1]).length;
      waiting.forEach(el => el.classList.add('reveal-pre'));
      return { n: waiting.length, moved, aboveFold: waiting.filter(el => el.getBoundingClientRect().top < innerHeight).length };
    });
    check(pend.n > 0, 'motion: nothing waits to be revealed below the fold');
    check(pend.moved === 0, `motion: hiding ${pend.moved} blocks for the reveal changes the layout`);
    check(pend.aboveFold === 0, `motion: ${pend.aboveFold} blocks in view at load are hidden`);
    await scrollThrough(mp);
    await mp.waitForFunction(() => [...document.querySelectorAll('.reveal')].every(el => getComputedStyle(el).opacity === '1' && getComputedStyle(el).transform === 'none'), null, { timeout: 30000 }).catch(() => {});
    const unshown = await mp.evaluate(() => [...document.querySelectorAll('.reveal')].filter(el => getComputedStyle(el).opacity !== '1' || getComputedStyle(el).transform !== 'none').length);
    check(unshown === 0, `motion: ${unshown} blocks never arrived after scrolling through the page`);
    await mp.evaluate(() => window.scrollTo(0, 0));

    // Language menu: opens to full size, then shrinks away and is hidden.
    await mp.click('.lang-btn');
    await mp.waitForFunction(() => { const cs = getComputedStyle(document.querySelector('.lang-menu')); return cs.opacity === '1' && (cs.transform === 'none' || cs.transform === 'matrix(1, 0, 0, 1, 0, 0)'); }, null, { timeout: 30000 }).catch(() => {});
    const open = await mp.evaluate(() => { const cs = getComputedStyle(document.querySelector('.lang-menu')); return [cs.opacity, cs.transform, cs.visibility]; });
    check(open[0] === '1' && (open[1] === 'none' || open[1] === 'matrix(1, 0, 0, 1, 0, 0)') && open[2] === 'visible', 'motion: language menu is not fully open: ' + open.join(' '));
    await mp.keyboard.press('Escape');
    check(await mp.locator('.lang-menu.is-closing').count() === 1, 'motion: language menu does not animate shut');
    check(await menuOpen(mp) === false, 'motion: language menu did not close on Escape');
    await mp.waitForFunction(() => !document.querySelector('.lang-menu').classList.contains('is-closing'), null, { timeout: 30000 }).catch(() => {});
    const shut = await mp.evaluate(() => [document.querySelector('.lang-menu').classList.contains('is-closing'), getComputedStyle(document.querySelector('.lang-menu')).visibility]);
    check(shut[0] === false && shut[1] === 'hidden', 'motion: language menu is not hidden after closing: ' + shut.join(' '));
    check(await mp.evaluate(() => document.activeElement.classList.contains('lang-btn')), 'motion: focus did not return to the language button');

    // Copy: the label is Copied at once; the old label is only a ghost that goes away.
    const cb = mp.locator('[data-copy]').first();
    await cb.scrollIntoViewIfNeeded();
    await cb.click();
    check((await cb.innerText()).trim() === 'Copied', 'motion: copy did not say Copied at once');
    check(await cb.getAttribute('data-prev') === 'Copy', 'motion: copy button has no ghost of the old label');
    await cb.evaluate(b => new Promise(done => { const until = Date.now() + 30000; (function poll() { if ((!b.hasAttribute('data-prev') && !b.getAnimations({ subtree: true }).some(a => a.playState === 'running')) || Date.now() > until) done(); else setTimeout(poll, 50); })(); }));
    check(await cb.getAttribute('data-prev') === null, 'motion: copy button keeps its ghost label');
    check(await cb.evaluate(b => b.getAnimations({ subtree: true }).filter(a => a.playState === 'running').length) === 0, 'motion: copy button is still animating');
    await sleep(1300);
    check((await cb.innerText()).trim() === 'Copy', 'motion: copy button did not go back to Copy');

    // Install tabs: the sliding fill lands on the selected tab, and the panel changes.
    await mp.click('[data-tab="src"]');
    const inkSettled = () => {
      const on = document.querySelector('.tabs [aria-selected="true"]'), i = document.querySelector('.tabs-ink');
      const ir = i.getBoundingClientRect(), br = on.getBoundingClientRect();
      return !i.getAnimations().some(a => a.playState === 'running') && Math.abs(ir.left - br.left) < 1 && Math.abs(ir.width - br.width) < 1;
    };
    await mp.waitForFunction(inkSettled, null, { timeout: 30000 }).catch(() => {});
    const ink = await mp.evaluate(() => {
      const on = document.querySelector('.tabs [aria-selected="true"]'), i = document.querySelector('.tabs-ink');
      const ir = i.getBoundingClientRect(), br = on.getBoundingClientRect();
      return { dx: Math.abs(ir.left - br.left), dw: Math.abs(ir.width - br.width), panel: document.querySelector('.panel.active').dataset.panel };
    });
    check(ink.dx < 1 && ink.dw < 1 && ink.panel === 'src', `motion: tab fill is off by ${ink.dx}/${ink.dw}px or panel is ${ink.panel}`);
    await pickLang(mp, 'de');
    await mp.waitForFunction(inkSettled, null, { timeout: 30000 }).catch(() => {});
    const inkDe = await mp.evaluate(() => {
      const on = document.querySelector('.tabs [aria-selected="true"]'), i = document.querySelector('.tabs-ink');
      return Math.abs(i.getBoundingClientRect().width - on.getBoundingClientRect().width);
    });
    check(inkDe < 1, `motion: tab fill does not follow a language change (off by ${inkDe}px)`);
    await pickLang(mp, 'en');
    await sleep(100);

    // FAQ: an answer opens to its full height and closes again.
    const d = mp.locator('.faq details').first();
    await d.locator('summary').scrollIntoViewIfNeeded();
    await d.locator('summary').click();
    // Up to five seconds for the motion to end: a busy machine runs it late, not differently.
    await d.evaluate(el => new Promise(done => { const t0 = performance.now(); (function poll() {
      const a = [...el.querySelectorAll('.a')].find(x => x.getClientRects().length);
      if ((a && a.getBoundingClientRect().height > 20) || performance.now() - t0 > 5000) done(); else requestAnimationFrame(poll); })(); }));
    const faqH = await d.evaluate(el => { const a = [...el.querySelectorAll('.a')].find(x => x.getClientRects().length); return a ? a.getBoundingClientRect().height : 0; });
    check(faqH > 20, `motion: FAQ answer is ${faqH}px tall after opening`);
    await d.locator('summary').click();
    await d.evaluate(el => new Promise(done => { const t0 = performance.now(); (function poll() {
      if ((getComputedStyle(el, '::details-content').blockSize === '0px' && !el.open) || performance.now() - t0 > 5000) done(); else requestAnimationFrame(poll); })(); }));
    check(await d.evaluate(el => getComputedStyle(el, '::details-content').blockSize === '0px' && !el.open), 'motion: FAQ answer still shown after closing');

    // A failed copy says so and shakes.
    await mp.evaluate(clipDenied);
    await mp.evaluate(() => window.scrollTo(0, 0));
    await cb.click();
    check((await cb.innerText()).trim() === 'Copy failed', 'motion: failed copy did not say Copy failed');
    check(await cb.evaluate(b => b.getAnimations().some(a => a.effect.getKeyframes().some(k => String(k.transform).includes('translateX')))), 'motion: failed copy does not shake');
    await mp.setViewportSize({ width: 390, height: 844 });
    await scrollThrough(mp);
    const wide = await mp.evaluate(() => { window.scrollTo(1000, 0); return [window.scrollX, document.documentElement.scrollWidth, innerWidth]; });
    check(wide[0] === 0, `motion, mobile: page scrolls sideways by ${wide[0]}px (page ${wide[1]}, screen ${wide[2]})`);
    await mctx.close();
  }

  await browser.close();
  if (failures.length) {
    console.error(failures.map(f => 'FAIL ' + f).join('\n'));
    process.exit(1);
  }
  console.log(`site OK: ${langs.length} languages, images, version badge, meta tags, anchors, tour, copy buttons, failed copies, persistence, locale detection, mobile width, text fits its box, motion and Reduce Motion`);
})().catch(e => { console.error(e); process.exit(1); });
