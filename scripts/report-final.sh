#!/usr/bin/env bash
# 修复：cancelled 不再被改写成 failed；失败时回传日志关键行，页面可直接展示原因。
set -euo pipefail
: "${WORKER_URL:?}"; : "${REPORT_TOKEN:?}"; : "${BUILD_ID:?}"; : "${JOB_STATUS:?}"; : "${GITHUB_REPOSITORY:?}"
URL=""; TAIL=""
case "$JOB_STATUS" in
  success)   STATUS=success; URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/build-${BUILD_ID}" ;;
  cancelled) STATUS=cancelled ;;
  *)         STATUS=failed
             [ -f /tmp/make.log ] && TAIL=$(grep -E "error:|Error [0-9]+|\*\*\*|missing dependencies|No space left" /tmp/make.log | tail -n 30 || true) ;;
esac
[ -s /tmp/config-error ] && TAIL="$(cat /tmp/config-error)
$TAIL"
[ -s /tmp/missing-packages ] && TAIL="未生效的插件（依赖缺失或源码里不存在）：$(tr '\n' ' ' </tmp/missing-packages)
$TAIL"
jq -n --arg b "$BUILD_ID" --arg s "$STATUS" --arg u "$URL" --arg t "$TAIL" \
  '{build_id:$b,status:$s,download_url:$u,log_tail:$t}' | curl -sf -X POST "$WORKER_URL/api/report" \
  -H "X-Report-Token: $REPORT_TOKEN" -H "Content-Type: application/json" --data-binary @-
