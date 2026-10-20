#!/usr/bin/env python3
"""把根目录 catalog.json 嵌入 worker/index.js 作为「内置回退目录」。
Worker 平时会从你的仓库在线读取 catalog.json，内置副本只在读取失败时兜底。
用法：python3 tools/build_worker.py"""
import json, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'worker', 'index.js')
cat = json.load(open(os.path.join(ROOT, 'catalog.json'), encoding='utf-8'))
blob = json.dumps(cat, ensure_ascii=False, separators=(',', ':'))
src = open(W, encoding='utf-8').read()
new, n = re.subn(r'/\*CATALOG:BEGIN\*/.*?/\*CATALOG:END\*/', lambda m: '/*CATALOG:BEGIN*/' + blob + '/*CATALOG:END*/', src, count=1, flags=re.S)
assert n == 1, '未找到 CATALOG 标记'
open(W, 'w', encoding='utf-8').write(new)
print(f'已嵌入 {len(cat["plugins"])} 个插件（{len(blob) // 1024} KB）')
