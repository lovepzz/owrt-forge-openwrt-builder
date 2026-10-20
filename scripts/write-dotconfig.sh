#!/usr/bin/env bash
set -euo pipefail
: "${HAS_DOTCONFIG:?}"
if [ "$HAS_DOTCONFIG" = "true" ]; then
  # 固定了配置底稿：原样使用该版本，不再叠加机型和插件清单，避免旧选择里已去掉的插件残留
  jq -r .dotconfig_snapshot config.json > openwrt/.config
  (cd openwrt && make defconfig)
elif [ "$(jq '(.packages // []) | length' config.json)" -gt 0 ] || [ -n "$(jq -r '.profile // ""' config.json)" ]; then
  bash "$SCRIPTS_DIR/gen-config.sh"
fi
