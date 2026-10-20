#!/usr/bin/env bash
# 由「机型 + 插件清单」生成 .config，分两步，让源码自己生成默认配置：
#   ① 只写目标平台和机型 → make defconfig → 得到该机型的默认配置，并确认机型真的生效
#   ② 再追加所选插件 → make defconfig → 逐个确认插件真的生效
# 机型不存在、或有插件没生效（依赖缺失 / 源码里没有这个包），直接失败并说明原因，
# 不会等编译几个小时后才发现固件里少了东西。
# 固定了配置底稿的任务不会走到这里（见 write-dotconfig.sh）。
set -euo pipefail
cd openwrt
T=$(jq -r '.target // ""' ../config.json)    # 例 mediatek/filogic、x86/64
P=$(jq -r '.profile // ""' ../config.json)   # 例 cmcc_rax3000m、generic
: > /tmp/missing-packages
: > /tmp/config-error

# target/profile 会被写进 .config，必须严格校验，防止注入额外的配置行
if [ -n "$P" ]; then
  [[ "$P" =~ ^[A-Za-z0-9_.+-]+$ ]] || { echo "::error::profile 格式非法: $P"; exit 1; }
  [[ "$T" =~ ^[A-Za-z0-9_+-][A-Za-z0-9_.+-]*/[A-Za-z0-9_+-][A-Za-z0-9_.+-]*$ ]] || { echo "::error::target 格式非法: $T"; exit 1; }
fi

# 不叠加任何旧配置：模板里的机型和插件清单就是唯一来源
rm -f .config

if [ -n "$P" ]; then
  m="${T%%/*}"; s="${T##*/}"
  printf 'CONFIG_TARGET_%s=y\nCONFIG_TARGET_%s_%s=y\nCONFIG_TARGET_%s_%s_DEVICE_%s=y\n' "$m" "$m" "$s" "$m" "$s" "$P" > .config
  make defconfig
  if ! grep -q "^CONFIG_TARGET_${m}_${s}_DEVICE_${P}=y" .config; then
    echo "机型 ${P} 在 ${T} 里不存在或没有生效。请回到模板页重新选择机型（源码版本可能改过机型名）。" | tee /tmp/config-error
    echo "::error::$(cat /tmp/config-error)"
    exit 1
  fi
  echo "已生成 ${T} / ${P} 的默认配置"
fi

# 追加所选插件，再让源码补全依赖
jq -r '.packages[]? | select(test("^[A-Za-z0-9_.+-]+$")) | "CONFIG_PACKAGE_\(.)=y"' ../config.json >> .config
make defconfig

for p in $(jq -r '.packages[]?' ../config.json); do
  grep -q "^CONFIG_PACKAGE_${p}=y" .config || echo "$p" >> /tmp/missing-packages
done
if [ -s /tmp/missing-packages ]; then
  echo "::error::以下插件 defconfig 后没有生效：$(tr '\n' ' ' < /tmp/missing-packages)"
  if [ -n "$P" ]; then
    exit 1      # 机型已确定，缺了插件就是真的缺：直接失败，省掉几小时无效编译
  fi
  echo "::warning::未选择机型，按警告处理，继续进入 menuconfig"
fi
exit 0
