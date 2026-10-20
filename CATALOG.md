# 插件目录 catalog.json 说明

插件商店的全部数据都在项目根目录的 `catalog.json`，**更新插件信息不需要改 Worker 代码，也不需要重新部署**。

## 文件分工

| 文件 | 谁来改 | 作用 |
|---|---|---|
| `catalog.json` | 脚本生成（也可手改） | Worker 实际读取的目录 |
| `catalog-src/overrides.json` | **你手工维护** | 中文名、说明、体积、推荐、分类、第三方插件、源码与设备列表 |
| `catalog.schema.json` | 一般不改 | 格式的 JSON Schema，编辑器里可用来补全和校验 |
| `tools/sync_catalog.py` | 一般不改 | 从 ImmortalWrt luci 仓库同步，合并手工维护区，生成 `catalog.json` |
| `tools/build_worker.py` | 一般不改 | 把目录嵌入 Worker 作为离线回退副本 |
| `.github/workflows/sync-catalog.yml` | 一般不改 | 每周自动同步并提交 |

## Worker 如何读取

1. 优先在线读取 `https://raw.githubusercontent.com/<你的编译仓库>/HEAD/catalog.json`（缓存约 5 分钟）。
2. 读取失败或内容无效时，使用嵌入在 `worker/index.js` 里的内置副本。
3. 商店页顶部显示目录更新日期和来源，点「刷新目录」可跳过缓存立即重读。
4. 在线读取到的数据会先过滤：包名必须是字母数字等安全字符，git/feed 地址必须是 https，不合格的条目会被丢弃，不会进入编译配置。

> 编译仓库需要是公开仓库（raw 地址才能匿名读取）。私有仓库只会使用内置副本，更新后需运行 `python3 tools/build_worker.py` 并重新粘贴 Worker。

## 顶层结构

```json
{
  "schema": 1,
  "updated": "2026-10-18",
  "upstream": { "repo": "https://github.com/immortalwrt/luci", "branch": "openwrt-24.10", "commit": "80ed8a44…" },
  "categories": [ { "id": "代理", "order": 1, "keywords": "科学 上网 分流 订阅" } ],
  "sources":    [ { "id": "immortalwrt-24.10", "name": "ImmortalWrt", "repo_url": "https://github.com/immortalwrt/immortalwrt", "branch": "openwrt-24.10" } ],
  "plugins":    [ … ]
}
```

- `categories[].keywords`：搜索别名，让中文关键词能搜到该分类下的英文插件。
- `sources`：商店里「项目（源码）」下拉框里的内置项目。**平台、子平台、机型不在这里维护**，Worker 会运行时直接去该仓库的 `target/linux` 读取，见下文「平台与机型」。

## 插件条目

```json
{
  "id": "luci-app-passwall",
  "name": "PassWall",
  "desc": "多节点、分流规则完整的代理工具。",
  "desc_en": "LuCI support for PassWall",
  "cat": "代理",
  "kind": "app",
  "origin": { "type": "builtin" },
  "deps": ["xray-core", "chinadns-ng"],
  "requires": [],
  "size_mb": 1.8,
  "rec": false,
  "tut": "装好后先添加订阅，再选择分流模式。",
  "tags": [],
  "hidden": false
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | OpenWrt 包名，唯一。会生成 `CONFIG_PACKAGE_<id>=y` |
| `name` | 是 | 显示名，优先中文 |
| `desc` / `desc_en` | 否 | 中文说明 / 上游英文原文。没翻译时两者相同 |
| `cat` | 是 | 必须是 `categories[].id` 之一 |
| `kind` | 是 | `app`（应用）、`theme`（主题）、`proto`（网络协议） |
| `origin` | 是 | 源码来源，见下 |
| `deps` | 否 | 上游声明的依赖，仅展示，由编译系统自动解决 |
| `requires` | 否 | 选中该插件时必须额外选中的包（如 `luci-compat`） |
| `size_mb` | 否 | 体积估算，未知填 `null`；清单只统计已知项 |
| `rec` | 否 | `true` 时显示「推荐内置」标记 |
| `tut` | 否 | 使用提示，显示在详情里 |
| `tags` | 否 | 该插件专属搜索词 |
| `hidden` | 否 | `true` 时商店不显示但保留记录 |

### origin 的三种写法

```json
{ "type": "builtin" }
```
已经在所选源码的 feeds 里，只需选中。

```json
{ "type": "git", "name": "luci-app-socat", "url": "https://github.com/mylucien/luci-app-socat", "branch": "", "sparse": false, "dirs": [] }
```
克隆进 `package/`。大仓库用 `"sparse": true` 并在 `dirs` 里列出需要的子目录。

```json
{ "type": "feed", "name": "istore", "line": "src-git istore https://github.com/linkease/istore;main" }
```
追加一个 feed 并更新，之后统一 `feeds install -a`。

## 常见更新操作

**修改某个插件的中文名、说明、体积、分类**
编辑 `catalog-src/overrides.json` 的 `overrides`，以包名为键，可写的字段有 `name`、`desc`、`cat`、`tut`、`size_mb`、`rec`、`requires`、`tags`、`hidden`：
```json
"luci-app-ddns-go": { "desc": "自动把公网 IP 解析到你的域名。", "size_mb": 3, "tut": "打开 9876 端口，填写服务商密钥。" }
```
然后运行 `python3 tools/sync_catalog.py` 并提交 `catalog.json`。

**新增第三方插件**
在 `overrides.json` 的 `extras` 里按「插件条目」格式追加一项（必须含 `origin`、`deps`、`requires`、`tags`），再同步。

**隐藏某个插件**
`"overrides": { "luci-app-xxx": { "hidden": true } }`

**新增或调整分类**
在 `categories` 里加一项（`order` 决定顺序）。想让脚本自动归类，在 `category_rules` 里加关键词（包名包含即命中，靠前的规则优先）。

**新增内置源码项目**
编辑 `overrides.json` 的 `sources`（`id` 只能用小写字母、数字、点、下划线、连字符）。个人用的项目更方便的做法是直接在商店里「添加自定义项目」，不用改文件。

**跟进上游新增和删除的插件**
不用做任何事：每周的 `sync-catalog` 工作流会自动同步并提交。想立即更新就手动运行该工作流，或本地执行 `python3 tools/sync_catalog.py`。
上游删除的插件如果还留在 `overrides` 里，同步时会打印警告，可以顺手清理。

## 校验

```bash
python3 tools/sync_catalog.py --validate-only
```
检查 id 唯一且合法、分类存在、origin 格式、requires 包名、体积取值、源码地址等。同步脚本在写入前也会自动校验，不合格则不会覆盖现有文件。

## 本地命令速查

```bash
python3 tools/sync_catalog.py                    # 克隆上游并生成 catalog.json
python3 tools/sync_catalog.py --luci-dir ./luci  # 用本地已克隆的 luci 仓库
python3 tools/sync_catalog.py --branch openwrt-23.05
python3 tools/build_worker.py                    # 更新 Worker 里的内置回退副本
```

## 平台与机型（实时读取，无需维护）

商店里的「平台 → 子平台 → 机型」不来自任何数据文件，而是 Worker 在你选择时直接去源码仓库读取：

1. **平台列表**：读取仓库 `target/linux/` 的目录列表（GitHub contents API，1 次调用）。
2. **子平台与机型**：选定平台后，读取 `target/linux/<平台>/Makefile`（子平台列表）、`image/` 目录下的 `*.mk`（机型定义）和各子平台的 `target.mk`（名称、架构），解析 `define Device/<id>` 与 `TARGET_DEVICES`。`<id>` 就是 profile，对应 `CONFIG_TARGET_<平台>_<子平台>_DEVICE_<id>=y`。
3. 解析结果缓存在 Worker 的 D1 里 7 天；页面上的「刷新」按钮会跳过缓存重新读取。

**自定义项目**：在项目下拉框选「＋ 添加 / 管理自定义项目」，填名称、GitHub 仓库地址和分支即可。添加时会立即检查仓库里有没有 `target/linux`，通过后平台和机型同样实时读取。目前只支持公开的 GitHub 仓库。

**为什么要用 token**：GitHub 的无令牌接口每个 IP 每小时只有 60 次，而 Cloudflare Worker 的出口 IP 是共享的，很容易被占满。所以 Worker 会带上你在部署向导里填的 GitHub token（只用来读公开仓库，每小时 5000 次）。实际用量很低：一个项目一周只需要几次到几十次调用。

**读取失败时**：页面会显示原因和「重试」按钮。平台、子平台、机型只能从下拉框里选，不支持手填，读取成功后才能生成模板；机型很多时，下拉框旁的输入框只用来筛选选项。

**子请求数量**：读取一个平台最多约 25 个子请求（`ath79` 这类文件很多的平台最多），低于 Cloudflare 免费版的 50 个上限。


## 自定义插件

商店里「＋ 自定义插件」添加的插件保存在 Worker 的 D1 里（`custom_plugins`），不会写进 `catalog.json`，所以不受每周目录同步影响。它们和目录里的插件走同一套逻辑，等价于下面这种条目：

```json
{
  "id": "luci-app-xxx", "name": "luci-app-xxx", "cat": "自定义", "custom": true,
  "origin": { "type": "git", "name": "luci-app-xxx", "url": "https://github.com/用户/仓库",
              "branch": "", "sparse": false, "dirs": [] },
  "requires": []
}
```

- **只支持 https 仓库地址**，包名和目录名都会严格校验；同一个仓库里的多个子目录会合并成一次稀疏克隆。
- **自动识别**：根目录有 `Makefile` 就当作单个包（包名取 `PKG_NAME`，没有则用仓库名）；否则列出 3 层以内带 `Makefile` 的子目录供勾选，包名取目录名。非 GitHub 仓库无法识别，需手填包名。
- 与目录里已有的插件同名会被拒绝；克隆到 `package/` 时，同名的源码自带包会被替换。
- 模板里保存的是展开后的来源，所以之后即使从商店删除了这个自定义插件，已有模板仍能照常编译。
