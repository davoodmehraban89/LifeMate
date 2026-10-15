#!/usr/bin/env python3
"""Validate the static public review boundary; no server/login tests implied."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import json

root = Path(__file__).resolve().parents[1] / 'site/review'
class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.html = {}; self.refs = []; self.title = False; self.h1 = 0
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'html': self.html = a
        if tag == 'h1': self.h1 += 1
        if tag == 'title': self.title = True
        assert tag not in {'script', 'iframe', 'form', 'input', 'textarea'}, f'No collection/embed/script: {tag}'
        for key in ['src', 'href']:
            if a.get(key): self.refs.append((tag, key, a[key], a))
        if tag == 'button': assert 'disabled' in a, 'Login must stay unavailable until real auth is approved and connected'

assert (root / 'CNAME').read_text().strip() == 'app.lifeguide.ir'
assert (root / '.nojekyll').is_file()
pages = list(root.glob('*.html'))
assert len(pages) >= 3, 'Include introduction, privacy and terms/support information'
for path in pages:
    source = path.read_text()
    p = Page(); p.feed(source)
    assert p.html.get('lang') == 'fa' and p.html.get('dir') == 'rtl', path.name
    assert p.title and p.h1 == 1, f'Single accessible page title and H1: {path.name}'
    assert 'LifeGuide' in source and 'لایف‌گاید' in source, f'Product identity: {path.name}'
    branding = source.replace('https://github.com/davoodmehraban89/LifeMate', '')
    assert not any(x.lower() in branding.lower() for x in ['LifeMate', 'up.railway.app', 'googleapis.com', 'gstatic.com']), path.name
    for tag, key, ref, attrs in p.refs:
        u = urlsplit(ref)
        if u.scheme or u.netloc:
            assert tag == 'a' and key == 'href' and u.scheme == 'https' and u.hostname == 'github.com', f'External runtime dependency or invented contact: {path.name}'
            if attrs.get('target') == '_blank': assert 'noopener' in attrs.get('rel', '').split()
            continue
        if not u.path: continue
        target = (path.parent / u.path.lstrip('/')).resolve()
        if target.is_dir(): target = target / 'index.html'
        assert target.is_relative_to(root.resolve()) and target.is_file(), f'Missing/escaping local reference: {path.name}: {ref}'
for path in root.rglob('*'):
    assert not path.is_symlink(), 'Only owned static files in public artifact'
    if path.is_file():
        assert path.suffix not in {'.jks', '.keystore', '.dump', '.env', '.pem', '.key'}, 'No private artifacts'
        assert path.stat().st_size < 5_000_000, 'Keep public review fast and bounded'
        if path.suffix == '.css':
            css=path.read_text().lower()
            assert 'http:' not in css and 'https:' not in css and '@import' not in css, 'Local CSS/fonts only'
print(json.dumps({'status':'PASS','scope':'static public product review; login/backend/SMS not exercised','htmlPages':len(pages)}, ensure_ascii=False))
