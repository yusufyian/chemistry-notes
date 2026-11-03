#!/usr/bin/env bash
#
# API 推送通道 —— 当 git smart-HTTP 被代理阻断时的备用方案
#
# 原理：用 GitHub Git Data API 直接构造 blob / tree / commit 并更新远端 ref，
#       完全绕开 git 传输层（git-upload-pack / git-receive-pack）。
#
# 用法：
#   ./push-via-api.sh              # 推送本地工作区已提交的内容到 origin/main
#   ./push-via-api.sh "提交信息"    # 自定义提交信息
#
set -euo pipefail

cd "$(dirname "$0")"

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}警告:${RESET} $*"; }
error() { echo "${RED}错误:${RESET} $*" >&2; exit 1; }

REPO="yusufyian/chemistry-notes"
BRANCH="main"

command -v gh >/dev/null || error "需要 gh CLI（brew install gh）"
command -v python3 >/dev/null || error "需要 python3"
gh auth status >/dev/null 2>&1 || error "gh 未登录，请先执行 gh auth login"

TMPDIR_API=$(mktemp -d)
trap 'rm -rf "$TMPDIR_API"' EXIT

# ---------------------------------------------------------------
# 1. 读取远端状态
# ---------------------------------------------------------------
REMOTE_SHA=$(gh api "repos/${REPO}/git/ref/heads/${BRANCH}" --jq '.object.sha' 2>/dev/null | tr -d '\n\r' || echo "")
REMOTE_TREE=""
if [[ -n "$REMOTE_SHA" ]]; then
  # 远端 commit 可能因异常中断而不存在，此时退回用本地做全量比对
  REMOTE_TREE=$(gh api "repos/${REPO}/git/commits/${REMOTE_SHA}" --jq '.tree.sha' 2>/dev/null | tr -d '\n\r' || echo "")
  if [[ -z "$REMOTE_TREE" ]]; then
    warn "远端 commit ${REMOTE_SHA:0:8} 不可用（可能为中断的残留），将重建分支"
    REMOTE_SHA=""
  fi
fi

info "远端 HEAD : ${REMOTE_SHA:-<无>}"

# ---------------------------------------------------------------
# 2. 收集需要变更的文件
# ---------------------------------------------------------------
# 以远端 tree 为基线，逐路径比对本地 HEAD
CHANGED=""
DELETED=""
if [[ -n "$REMOTE_SHA" ]]; then
  CHANGED=$(git diff --diff-filter=AM --name-only "$REMOTE_TREE" HEAD 2>/dev/null || git ls-tree -r --name-only HEAD)
  DELETED=$(git diff --diff-filter=D --name-only "$REMOTE_TREE" HEAD 2>/dev/null || echo "")
else
  CHANGED=$(git ls-tree -r --name-only HEAD)
  DELETED=""
fi

ENTRIES=()
COUNT=0

for path in $CHANGED; do
  # 跳过私密路径
  case "$path" in
    private/*|content/private/*|templates/*|content/templates/*) continue ;;
  esac

  BLOB_SHA=$(git rev-parse "HEAD:${path}" 2>/dev/null || continue)
  MODE=$(git ls-tree HEAD "${path}" | awk '{print $1}')

  # 上传 blob（远端已有同 sha 则跳过）
  if ! gh api "repos/${REPO}/git/blobs/${BLOB_SHA}" --jq '.sha' >/dev/null 2>&1; then
    BLOB_JSON="$TMPDIR_API/blob.json"
    git cat-file blob "$BLOB_SHA" | python3 -c "
import sys, json, base64
data = sys.stdin.buffer.read()
sys.stdout.write(json.dumps({'content': base64.b64encode(data).decode(), 'encoding': 'base64'}))
" > "$BLOB_JSON"
    gh api "repos/${REPO}/git/blobs" --method POST --input "$BLOB_JSON" >/dev/null
    COUNT=$((COUNT + 1))
    echo "  上传: ${path}"
  fi

  ENTRIES+=("$(python3 - "$path" "$MODE" "$BLOB_SHA" <<'PYEOF'
import json, sys
sys.stdout.write(json.dumps({
    "path": sys.argv[1], "mode": sys.argv[2],
    "type": "blob", "sha": sys.argv[3],
}))
PYEOF
)")
done

for path in $DELETED; do
  ENTRIES+=("$(python3 - "$path" <<'PYEOF'
import json, sys
sys.stdout.write(json.dumps({
    "path": sys.argv[1], "mode": "100644", "type": "blob", "sha": None,
}))
PYEOF
)")
done

info "新上传 ${COUNT} 个 blob，共 ${#ENTRIES[@]} 个树条目"

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
  info "没有内容变更。"
  exit 0
fi

# ---------------------------------------------------------------
# 3. 创建 tree
# ---------------------------------------------------------------
TREE_JSON="$TMPDIR_API/tree.json"
python3 - "$TREE_JSON" "$REMOTE_TREE" "${ENTRIES[@]}" <<'PYEOF'
import json, sys
out_path, base = sys.argv[1], sys.argv[2]
tree = [json.loads(e) for e in sys.argv[3:]]
payload = {"tree": tree}
if base:
    payload["base_tree"] = base
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False)
PYEOF

TREE_RESP=$(gh api "repos/${REPO}/git/trees" --method POST --input "$TREE_JSON" 2>&1) || {
  echo "$TREE_RESP" >&2
  error "创建 tree 失败"
}
NEW_TREE=$(echo "$TREE_RESP" | python3 -c "import json,sys; sys.stdout.write(json.load(sys.stdin).get('sha',''))")
[[ -z "$NEW_TREE" ]] && { echo "$TREE_RESP" >&2; error "创建 tree 失败"; }
info "新 tree: ${NEW_TREE:0:8}"

# ---------------------------------------------------------------
# 4. 创建 commit
# ---------------------------------------------------------------
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  MSG="$1"
else
  MSG="docs: 更新 ($(date '+%Y-%m-%d %H:%M'))"
fi

COMMIT_JSON="$TMPDIR_API/commit.json"
python3 - "$COMMIT_JSON" "$MSG" "$NEW_TREE" "$REMOTE_SHA" <<'PYEOF'
import json, sys
out_path, msg, tree, parent = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
payload = {"message": msg, "tree": tree, "parents": [parent] if parent else []}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False)
PYEOF

COMMIT_RESP=$(gh api "repos/${REPO}/git/commits" --method POST --input "$COMMIT_JSON" 2>&1) || {
  echo "$COMMIT_RESP" >&2
  error "创建 commit 失败"
}
NEW_COMMIT=$(echo "$COMMIT_RESP" | python3 -c "import json,sys; sys.stdout.write(json.load(sys.stdin).get('sha',''))")
[[ -z "$NEW_COMMIT" ]] && { echo "$COMMIT_RESP" >&2; error "创建 commit 失败"; }
info "新 commit: ${NEW_COMMIT:0:8}  ($MSG)"

# ---------------------------------------------------------------
# 5. 更新远端 ref
# ---------------------------------------------------------------
REF_JSON="$TMPDIR_API/ref.json"
printf '{"sha": "%s", "force": true}' "$NEW_COMMIT" > "$REF_JSON"
gh api "repos/${REPO}/git/refs/heads/${BRANCH}" --method PATCH --input "$REF_JSON" >/dev/null

info "远端已更新: ${NEW_COMMIT:0:8}"

# ---------------------------------------------------------------
# 6. 同步本地 git 状态
# ---------------------------------------------------------------
# API 通道创建的 commit 对象不在本地，先把对象取回来，
# 再把本地 main 指向同一个 commit，保证 git log 与远端一致。
if git fetch origin "$BRANCH" 2>/dev/null; then
  git reset --soft "$NEW_COMMIT" 2>/dev/null || true
  info "本地 git 状态已与远端同步"
else
  warn "无法 git fetch（传输层仍被阻断），本地 SHA 与远端暂不一致。"
  warn "内容已确认一致，可手动恢复：git fetch origin main && git reset --hard origin/main"
fi

info "完成。GitHub Actions 正在构建站点，通常 1-2 分钟内上线。"
echo ""
echo "站点地址: https://yusufyian.github.io/chemistry-notes/"
