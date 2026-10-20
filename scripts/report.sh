#!/usr/bin/env bash
# 用法：report.sh <build_id> <status> [key=value ...]
# 改用 jq 生成 JSON：web_url 含密码，手拼字符串遇到引号/反斜杠会直接坏掉。
set -euo pipefail
: "${WORKER_URL:?}"; : "${REPORT_TOKEN:?}"
BUILD_ID="${1:?用法: report.sh <build_id> <status> [key=value ...]}"; STATUS="${2:?}"; shift 2
args=(--arg build_id "$BUILD_ID" --arg status "$STATUS"); expr='{build_id:$build_id,status:$status}'
for kv in "$@"; do k="${kv%%=*}"; args+=(--arg "$k" "${kv#*=}"); expr+=" + {\"$k\":\$$k}"; done
jq -n "${args[@]}" "$expr" | curl -sf -X POST "$WORKER_URL/api/report" \
  -H "X-Report-Token: $REPORT_TOKEN" -H "Content-Type: application/json" --data-binary @-
