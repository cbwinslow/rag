#!/usr/bin/env python3
"""
gov_ingest.py

Fetch documents from govinfo.gov (API or bulk) and congress.gov and emit NDJSON usable by autorag ingestion.

Usage examples:
  python3 gov_ingest.py --source govinfo --path /collections/BILLS --api-key $GOVINFO_API_KEY --out bills.ndjson
  python3 gov_ingest.py --source worker --worker-url https://my-worker.example/fetch --path /docs/foo --out out.ndjson

The script is minimal and robust: it paginates where possible and emits one JSON object per line with fields: url, title, content, source
"""
import argparse
import json
import sys
import requests
from urllib.parse import urljoin
from hashlib import sha1
from bs4 import BeautifulSoup

def fetch_govinfo_api(path, api_key=None, params=None):
    base = 'https://api.govinfo.gov'
    url = urljoin(base, path)
    params = params or {}
    if api_key:
        params['api_key'] = api_key
    r = requests.get(url, params=params, timeout=30)
    r.raise_for_status()
    return r.json()

def fetch_direct(url):
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.text

def emit(obj, out):
    out.write(json.dumps(obj, ensure_ascii=False) + '\n')

def ingest_govinfo_collection(path, api_key, out):
    # simple pager example for collections endpoints
    page = 1
    pagesize = 100
    while True:
        params = {'offset': (page-1)*pagesize, 'pageSize': pagesize}
        resp = fetch_govinfo_api(path, api_key=api_key, params=params)
        items = resp.get('items') or resp.get('results') or []
        if not items:
            break
        for it in items:
            url = it.get('url') or it.get('downloadUrl') or it.get('link')
            title = it.get('title') or it.get('name') or ''
            content = ''
            try:
                if url:
                    content = fetch_direct(url)
            except Exception as e:
                content = f"<fetch-error>{str(e)}</fetch-error>"
            meta = extract_metadata(content)
            emit({'url': url, 'title': meta.get('title') or title, 'date': meta.get('date'), 'content': content, 'source': 'govinfo'}, out)
        if len(items) < pagesize:
            break
        page += 1

def ingest_worker(worker_url, path, out):
    target = worker_url
    if path:
        if '? ' in worker_url:
            target = f"{worker_url}&path={path}"
        else:
            target = f"{worker_url}?path={path}"
    r = requests.get(target, timeout=30)
    r.raise_for_status()
    # If JSON, output direct. If HTML, wrap
    if 'application/json' in r.headers.get('content-type',''):
        data = r.json()
        meta = extract_metadata(data.get('content') or '')
        emit({'url': data.get('url'), 'title': meta.get('title') or '', 'date': meta.get('date'), 'content': data.get('content'), 'source': 'worker'}, out)
    else:
        meta = extract_metadata(r.text)
        emit({'url': target, 'title': meta.get('title') or '', 'date': meta.get('date'), 'content': r.text, 'source': 'worker'}, out)


_SEEN=set()
def dedupe_and_emit(record, out):
    key = record.get('url') or sha1((record.get('content') or '').encode('utf-8')).hexdigest()
    if key in _SEEN:
        return
    _SEEN.add(key)
    emit(record, out)

def extract_metadata(html_text):
    res={'title':None,'date':None}
    if not html_text:
        return res
    try:
        soup = BeautifulSoup(html_text, 'html.parser')
        if soup.title and soup.title.string:
            res['title'] = soup.title.string.strip()
        # find meta[name=date] or meta[property='article:published_time']
        m = soup.find('meta', attrs={'name':'date'}) or soup.find('meta', attrs={'property':'article:published_time'})
        if m and m.get('content'):
            res['date'] = m.get('content')
    except Exception:
        pass
    return res

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', choices=['govinfo','congress','worker'], required=True)
    p.add_argument('--path', help='API path or document path', default='')
    p.add_argument('--api-key', help='govinfo api key', default=None)
    p.add_argument('--worker-url', help='Worker fetch URL base (e.g. https://myworker.example/fetch)', default=None)
    p.add_argument('--out', help='Output NDJSON file', default='out.ndjson')
    p.add_argument('--push-worker', help='POST the NDJSON to worker /store after generation', action='store_true')
    p.add_argument('--worker-store-url', help='Worker store endpoint (e.g. https://myworker.example/store)', default=None)
    args = p.parse_args()

    out = open(args.out, 'w', encoding='utf-8')
    try:
        if args.source == 'govinfo':
            ingest_govinfo_collection(args.path or '/collections/BILLS', args.api_key, out)
        elif args.source == 'worker':
            if not args.worker_url:
                raise SystemExit('worker-url required for source=worker')
            ingest_worker(args.worker_url, args.path, out)
        elif args.source == 'congress':
            target = 'https://www.congress.gov' + (args.path or '/')
            content = fetch_direct(target)
            rec = {'url': target, 'title': '', 'content': content, 'source': 'congress'}
            dedupe_and_emit(rec, out)
    finally:
        out.close()

    if args.push_worker:
        if not args.worker_store_url:
            raise SystemExit('worker-store-url required when --push-worker is set')
        # push NDJSON to worker
        with open(args.out, 'rb') as f:
            r = requests.post(args.worker_store_url, data=f.read(), headers={'content-type':'application/x-ndjson'})
            r.raise_for_status()
            print('Pushed to worker store:', r.text)

if __name__ == '__main__':
    main()
