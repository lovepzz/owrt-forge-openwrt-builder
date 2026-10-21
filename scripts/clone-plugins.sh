#!/usr/bin/env bash
set -euo pipefail
export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
ROOT="$PWD"; mkdir -p openwrt/package
NAME_RE='^[A-Za-z0-9_.+-]+$'
URL_RE='^(https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/%+@-]+|git@[A-Za-z0-9.-]+:[A-Za-z0-9._~/+-]+)$'
DIR_RE='^[A-Za-z0-9._+/-]+$'
# 很多 luci 应用的 Makefile 写的是 `include ../../luci.mk`（相对 luci feed 的位置），放进 package/ 后找不到，
# 整个包会被 OpenWrt 扫描时悄悄丢掉。统一改成不依赖位置的写法。
fix_luci_include() {
  find "$1" -name Makefile -print0 2>/dev/null | while IFS= read -r -d '' f; do
    if grep -qE 'include[[:space:]]+(\.\./)+luci\.mk' "$f"; then
      sed -i -E 's#include[[:space:]]+(\.\./)+luci\.mk#include $(TOPDIR)/feeds/luci/luci.mk#' "$f"
      echo "已修正 luci.mk 相对路径：${f#"$ROOT"/openwrt/}"
    fi
  done
}
jq -c '.plugins[]?' config.json | while read -r p; do
  name=$(jq -r .name <<<"$p")
  [[ "$name" =~ $NAME_RE ]] || { echo "::error::插件目录名非法: $name"; exit 1; }
  # feed 类插件（如 iStore）：追加到 feeds.conf.default 并单独更新，之后由 feeds install -a 安装
  feed=$(jq -r '.feed // empty' <<<"$p")
  if [ -n "$feed" ]; then
    [[ "$feed" =~ ^src-(git|git-full|link)\ [A-Za-z0-9_.-]+\ https://[^[:space:]]+$ ]] || { echo "::error::feed 行格式非法: $feed"; exit 1; }
    echo "$feed" >> "$ROOT/openwrt/feeds.conf.default"
    (cd "$ROOT/openwrt" && ./scripts/feeds update "$name")
    continue
  fi
  url=$(jq -r .git_url <<<"$p"); branch=$(jq -r '.branch // ""' <<<"$p")
  [[ "$url" =~ $URL_RE ]] || { echo "::error::插件仓库地址非法: $url"; exit 1; }
  # 分支可为空（使用仓库默认分支）；整仓克隆和稀疏克隆都会用到
  bopt=(); [ -n "$branch" ] && bopt=(-b "$branch")
  if [ "$(jq -r '.sparse // false' <<<"$p")" = "true" ]; then
    # 修复：url 以 .git 结尾时 basename 与 git clone 生成的目录名不一致，原脚本会 cd 失败
    tmp=$(mktemp -d); mapfile -t dirs < <(jq -r '.dirs[]' <<<"$p")
    for d in "${dirs[@]}"; do [[ "$d" =~ $DIR_RE && "$d" != /* && "$d" != *..* ]] || { echo "::error::子目录非法: $d"; exit 1; }; done
    git clone --depth=1 "${bopt[@]}" --single-branch --filter=blob:none --sparse -- "$url" "$tmp/r"
    git -C "$tmp/r" sparse-checkout set "${dirs[@]}"
    # 同名的源码自带包会被这里的版本替换（直接 mv 到已存在的目录里会变成嵌套目录）
    for d in "${dirs[@]}"; do rm -rf "$ROOT/openwrt/package/$(basename "$d")"; mv -f "$tmp/r/$d" "$ROOT/openwrt/package/$(basename "$d")"; fix_luci_include "$ROOT/openwrt/package/$(basename "$d")"; done
    rm -rf "$tmp"
  else
    rm -rf "$ROOT/openwrt/package/$name"
    git clone --depth 1 "${bopt[@]}" -- "$url" "$ROOT/openwrt/package/$name"
    fix_luci_include "$ROOT/openwrt/package/$name"
  fi
done
