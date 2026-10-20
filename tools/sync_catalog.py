#!/usr/bin/env python3
"""从 ImmortalWrt luci 仓库同步插件信息，合并 catalog-src/overrides.json，生成根目录 catalog.json。

用法：
  python3 tools/sync_catalog.py                    # 克隆上游并生成
  python3 tools/sync_catalog.py --luci-dir PATH    # 使用本地已克隆的 luci 仓库
  python3 tools/sync_catalog.py --validate-only    # 只校验现有 catalog.json
"""
import argparse, datetime, glob, hashlib, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'catalog-src', 'overrides.json')
OUT = os.path.join(ROOT, 'catalog.json')
PKG_RE = re.compile(r'^[A-Za-z0-9_.+-]+$')
FEED_RE = re.compile(r'^src-(git|git-full|link) [A-Za-z0-9_.-]+ https://\S+$')
FIELDS = ['id', 'name', 'desc', 'desc_en', 'cat', 'kind', 'origin', 'deps', 'requires', 'size_mb', 'rec', 'tut', 'tags', 'hidden']
OVERRIDABLE = {'name', 'desc', 'cat', 'tut', 'size_mb', 'rec', 'requires', 'tags', 'hidden'}


def read(p):
    return open(p, encoding='utf-8', errors='ignore').read()


def mk(path, key):
    m = re.search(r'^' + key + r'\s*:?=\s*((?:.*\\\n)*.*)$', read(path), re.M)
    return re.sub(r'\\\n\s*', ' ', m.group(1)).strip() if m else ''


def zh_title(pkgdir, title):
    for po in glob.glob(pkgdir + '/po/zh_Hans/*.po'):
        m = re.search(r'msgid "' + re.escape(title) + r'"\nmsgstr "(.+)"', read(po))
        if m:
            return m.group(1)
    return ''


def parse_luci(luci, dirs, menu_map):
    out = []
    for kind_dir, kind in dirs.items():
        base = os.path.join(luci, kind_dir)
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            mf = os.path.join(d, 'Makefile')
            if not os.path.isfile(mf):
                continue
            title = mk(mf, 'LUCI_TITLE').split(' | ')[0].strip()
            deps = [x.lstrip('+') for x in mk(mf, 'LUCI_DEPENDS').split() if x.startswith('+')]
            deps = [x for x in deps if x not in ('luci-base', 'luci-compat') and not x.startswith('@')]
            menu_title, menu_cat = '', ''
            for j in sorted(glob.glob(d + '/root/usr/share/luci/menu.d/*.json')):
                try:
                    dj = json.load(open(j, encoding='utf-8'))
                except Exception:
                    continue
                for k, v in dj.items():
                    seg = k.split('/')
                    if not menu_cat and len(seg) > 1 and seg[0] == 'admin' and seg[1] in menu_map:
                        menu_cat, menu_title = menu_map[seg[1]], v.get('title', '')
            short = re.sub(r'^luci-(app|theme|proto)-', '', name)
            out.append(dict(id=name, kind=kind, name=zh_title(d, menu_title) or menu_title or short,
                            desc_en=title, desc=title, deps=deps, _menu_cat=menu_cat))
    return out


def classify(p, rules, fallback):
    if p['kind'] == 'theme':
        return '主题'
    if p['kind'] == 'proto':
        return '协议'
    for r in rules:
        if any(k in p['id'] for k in r['match']):
            return r['cat']
    return p['_menu_cat'] or fallback


def validate(c):
    errs, ids = [], set()
    cats = {x['id'] for x in c.get('categories', [])}
    if c.get('schema') != 1:
        errs.append('schema 必须为 1')
    for p in c.get('plugins', []):
        i = p.get('id', '')
        if not PKG_RE.match(i):
            errs.append(f'非法 id: {i!r}')
        if i in ids:
            errs.append(f'重复 id: {i}')
        ids.add(i)
        if p.get('cat') not in cats:
            errs.append(f'{i}: 未知分类 {p.get("cat")!r}')
        if p.get('kind') not in ('app', 'theme', 'proto'):
            errs.append(f'{i}: kind 非法')
        o = p.get('origin') or {}
        if o.get('type') == 'git' and not str(o.get('url', '')).startswith('https://'):
            errs.append(f'{i}: git url 必须是 https')
        elif o.get('type') == 'feed' and not FEED_RE.match(o.get('line', '')):
            errs.append(f'{i}: feed line 格式非法')
        elif o.get('type') not in ('builtin', 'git', 'feed'):
            errs.append(f'{i}: origin.type 非法')
        if any(not PKG_RE.match(x) for x in p.get('requires', [])):
            errs.append(f'{i}: requires 含非法包名')
        s = p.get('size_mb')
        if s is not None and (not isinstance(s, (int, float)) or s < 0):
            errs.append(f'{i}: size_mb 必须是非负数或 null')
    for s in c.get('sources', []):
        if not re.match(r'^[a-z0-9][a-z0-9._-]*$', str(s.get('id', ''))) or not str(s.get('repo_url', '')).startswith('https://') or not s.get('branch'):
            errs.append(f'源码配置非法: {s}')
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--luci-dir')
    ap.add_argument('--branch')
    ap.add_argument('--validate-only', action='store_true')
    a = ap.parse_args()
    if a.validate_only:
        errs = validate(json.load(open(OUT, encoding='utf-8')))
        print('\n'.join(errs) or 'catalog.json 校验通过')
        sys.exit(1 if errs else 0)

    cfg = json.load(open(SRC, encoding='utf-8'))
    up = cfg['upstream']
    branch = a.branch or up['branch']
    luci, tmp = a.luci_dir, None
    if not luci:
        tmp = tempfile.mkdtemp()
        luci = os.path.join(tmp, 'luci')
        subprocess.check_call(['git', 'clone', '--depth', '1', '--filter=blob:none', '-b', branch, up['repo'], luci])
    commit = subprocess.run(['git', '-C', luci, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()

    plugins = parse_luci(luci, up['dirs'], cfg['menu_category_map'])
    fb = '其它'
    for p in plugins:
        p['cat'] = classify(p, cfg['category_rules'], fb)
        p.pop('_menu_cat')
        p.update(origin={'type': 'builtin'}, requires=[], size_mb=None, rec=False, tut='', tags=[], hidden=False)
    by = {p['id']: p for p in plugins}
    for k, v in cfg['overrides'].items():
        if k not in by:
            print(f'警告：overrides 里的 {k} 在上游已不存在，已忽略', file=sys.stderr)
            continue
        by[k].update({f: v[f] for f in v if f in OVERRIDABLE})
    for e in cfg['extras']:
        if e['id'] in by:
            print(f'警告：extras 里的 {e["id"]} 与上游重名，已忽略 extras 版本', file=sys.stderr)
            continue
        e.setdefault('desc_en', '')
        e.setdefault('hidden', False)
        plugins.append(e)
    order = {c['id']: c['order'] for c in cfg['categories']}
    plugins.sort(key=lambda p: (order.get(p['cat'], 999), p['id']))
    plugins = [{f: p.get(f, [] if f in ('deps', 'requires', 'tags') else None) for f in FIELDS} for p in plugins]

    cat = {'schema': 1, 'updated': datetime.date.today().isoformat(),
           'upstream': {'repo': up['repo'], 'branch': branch, 'commit': commit},
           'categories': sorted(cfg['categories'], key=lambda c: c['order']),
           'sources': cfg['sources'], 'plugins': plugins}
    errs = validate(cat)
    if errs:
        print('\n'.join(errs), file=sys.stderr)
        sys.exit(1)
    if os.path.exists(OUT):  # 内容没变就保持原更新日期，避免定时任务每周产生无意义提交
        try:
            prev = json.load(open(OUT, encoding='utf-8'))
            if {**prev, 'updated': None} == {**cat, 'updated': None}:
                cat['updated'] = prev['updated']
        except Exception:
            pass
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(cat, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'已生成 catalog.json：{len(plugins)} 个插件，上游 {branch}@{commit[:8]}')


if __name__ == '__main__':
    main()
