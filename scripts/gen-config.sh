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

  # 根文件系统分区大小：整盘镜像类目标（x86、armsr、rockchip、sunxi、bcm27xx）的默认值很小（x86 只有 104MB），
  # 装几个 luci 应用就会在生成 root.ext4 时报 "failed to allocate N blocks, out of space"，这里提到 1024MB。
  # 路由器常见的闪存固件（mediatek、ramips、ath79、qualcommax 等）用不到这个选项，不改。想要别的大小改 ROOTFS_MB（单位 MB）。
  ROOTFS_MB=1024
  case "$m" in x86|armsr|rockchip|sunxi|bcm27xx)
    cur=$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=//p' .config | head -n1)
    if [ -n "$cur" ] && [ "$cur" -lt "$ROOTFS_MB" ] 2>/dev/null; then
      sed -i "s/^CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=${ROOTFS_MB}/" .config
      echo "根文件系统分区 ${cur}MB → ${ROOTFS_MB}MB"
    fi ;;
  esac
fi

# 追加所选插件，再让源码补全依赖
jq -r '.packages[]? | select(test("^[A-Za-z0-9_.+-]+$")) | "CONFIG_PACKAGE_\(.)=y"' ../config.json >> .config
make defconfig

for p in $(jq -r '.packages[]?' ../config.json); do
  grep -q "^CONFIG_PACKAGE_${p}=y" .config || echo "$p" >> /tmp/missing-packages
done

# 逐个说明没生效的原因：源码里有没有这个包、自定义插件仓库里实际定义了哪些包名
diagnose() {
  local p f d names
  for p in $(cat /tmp/missing-packages); do
    f=$(grep -rlsE --include=Makefile "call BuildPackage,[[:space:]]*${p}[)[:space:]]|^PKG_NAME[[:space:]]*:?=[[:space:]]*${p}[[:space:]]*$" package feeds 2>/dev/null | head -n1 || true)
    if [ -n "$f" ]; then echo "- ${p}：在 ${f} 里有定义，但没被启用（依赖没满足，或不支持当前平台）"
    else echo "- ${p}：源码和 feeds 里都没有叫这个名字的包（包名要和 Makefile 里的 PKG_NAME 一致，不是目录名）"; fi
  done
  jq -r '.plugins[]? | select(.git_url) | (if .sparse then (.dirs[] | split("/") | last) else .name end)' ../config.json | sort -u | while read -r d; do
    if [ ! -d "package/$d" ]; then echo "- 自定义插件目录 package/$d 不存在"; continue; fi
    names=$(grep -rhoE --include=Makefile "(call BuildPackage,[[:space:]]*[A-Za-z0-9_.+-]+|^PKG_NAME[[:space:]]*:?=[[:space:]]*[A-Za-z0-9_.+-]+)" "package/$d" 2>/dev/null | sed -E 's/^.*[,=][[:space:]]*//' | sort -u | tr '\n' ' ' || true)
    echo "- package/$d 里的包名：${names:-（Makefile 里没找到 BuildPackage / PKG_NAME，luci 应用会按目录名 $d 生成）}"
  done
}

if [ -s /tmp/missing-packages ]; then
  { echo "有插件没生效："; diagnose; } > /tmp/config-error
  echo "::error::以下插件 defconfig 后没有生效：$(tr '\n' ' ' < /tmp/missing-packages)"
  cat /tmp/config-error
  if [ -n "$P" ]; then
    exit 1      # 机型已确定，缺了插件就是真的缺：直接失败，省掉几小时无效编译
  fi
  echo "::warning::未选择机型，按警告处理，继续进入 menuconfig"
fi
exit 0
