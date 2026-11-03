#!/usr/bin/env bash
#
# 同步脚本：提交并推送 content/ 下的全部改动到 GitHub
#
# 用法:
#   ./sync.sh                # 使用自动生成的提交信息
#   ./sync.sh "补充卤族数据"  # 使用自定义提交信息
#
set -euo pipefail

cd "$(dirname "$0")"

# 颜色输出
if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; RESET=""
fi

info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}警告:${RESET} $*"; }
error() { echo "${RED}错误:${RESET} $*" >&2; exit 1; }

# 1. 检查改动
if [[ -z "$(git status --porcelain)" ]]; then
  info "没有检测到改动，无需提交。"
  exit 0
fi

echo "--- 待提交的改动 ---"
git status --short
echo "------------------------"

# 2. 大文件检查（GitHub 硬限制 100MB，LFS 建议 50MB 以下）
LARGE_FILES=$(find content -type f -size +40M 2>/dev/null || true)
if [[ -n "$LARGE_FILES" ]]; then
  warn "以下文件超过 40MB，直接推送可能导致仓库膨胀或被 GitHub 拒绝："
  echo "$LARGE_FILES"
  echo ""
  warn "建议：把这些文件移到 NAS 或对象存储，在笔记中保留下载链接。"
  read -r -p "仍要继续？(y/N) " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || error "已取消"
fi

# 3. 暂存
git add -A

# 4. 提交信息
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  MSG="$1"
else
  CHANGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
  MSG="docs: 更新 ${CHANGED} 个文件 ($(date '+%Y-%m-%d %H:%M'))"
fi

git commit -m "$MSG"
info "已提交: $MSG"

# 5. 推送
info "推送到 origin/main ..."
if ! git push origin main; then
  error "推送失败。常见原因：网络代理不稳定。可重试，或先执行 git pull --rebase origin main"
fi

info "推送完成。GitHub Actions 正在构建站点，通常 1-2 分钟内上线。"
echo ""
echo "站点地址: https://yusufyian.github.io/chemistry-notes/"
