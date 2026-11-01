#!/usr/bin/env bash
#
# 把本仓库里的 naive-icons skill 装到本机各 AI 客户端的技能目录。
#
# 和 `npx skills add guokaigdg/naive-icons` 的区别：不联网、不依赖 npm，
# 直接用当前 clone 当源，默认建**软链**——改了仓库里的 SKILL.md / catalog.md，
# 各客户端立刻用上新内容，不用重装。
#
#   bash scripts/install_skill.sh                          # 预览会装到哪些目录
#   bash scripts/install_skill.sh --yes                    # 装（全局，软链）
#   bash scripts/install_skill.sh --copy --yes             # 复制而不是软链
#   bash scripts/install_skill.sh --project ~/code/my-app --yes   # 装进某个项目
#   bash scripts/install_skill.sh --target DIR --yes        # 只装到指定技能目录
#   bash scripts/install_skill.sh --target DIR --global --yes   # 指定目录 + 全局一起装
#   bash scripts/install_skill.sh --list                   # 看现在装到哪了
#   bash scripts/install_skill.sh --uninstall --yes        # 卸载
#
set -euo pipefail

SKILL_NAME="naive-icons"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/skills/$SKILL_NAME"

MODE="link"        # link | copy
SCOPE="global"     # global | project
FORCE_GLOBAL=0     # --global：即使给了 --target 也把全局目录一起装上
PROJECT_DIR=""
ASSUME_YES=0
UNINSTALL=0
LIST_ONLY=0
EXTRA_TARGETS=()

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
realpath_of() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)            ASSUME_YES=1 ;;
    --copy)              MODE="copy" ;;
    --link)              MODE="link" ;;
    --project)           SCOPE="project"; PROJECT_DIR="${2:?--project 需要一个目录}"; shift ;;
    --global)            FORCE_GLOBAL=1 ;;
    --target)            EXTRA_TARGETS+=("${2:?--target 需要一个目录}"); shift ;;
    --uninstall|--remove) UNINSTALL=1 ;;
    --list|--status)     LIST_ONLY=1 ;;
    -h|--help)           usage ;;
    *) die "未知参数：$1（用 --help 看用法）" ;;
  esac
  shift
done

[ -f "$SRC/SKILL.md" ] || die "找不到 $SRC/SKILL.md，请在 naive-icons 仓库里运行本脚本"

# 本机已存在的客户端技能目录。父目录不存在 = 没装那个客户端，跳过，
# 免得在用户机器上凭空造出一堆空目录。
global_targets() {
  local candidates=(
    "$HOME/.codex/skills"            # Codex
    "$HOME/.agents/skills"           # 通用 Agent 目录（Claude Code / Cursor / Codex 都读）
    "$HOME/.claude/skills"           # Claude Code
    "$HOME/.config/opencode/skills"  # OpenCode
    "$HOME/.gemini/skills"           # Gemini CLI
    "$HOME/.cursor/skills"           # Cursor
  )
  local d
  for d in "${candidates[@]}"; do
    if [ -d "$d" ]; then printf '%s\n' "$d"; fi
  done
  return 0
}

project_targets() {
  [ -n "$PROJECT_DIR" ] || die "--project 需要一个目录"
  [ -d "$PROJECT_DIR" ] || die "项目目录不存在：$PROJECT_DIR"
  printf '%s\n' "$PROJECT_DIR/.claude/skills" "$PROJECT_DIR/.agents/skills"
  return 0
}

# 目标集合：
#   裸跑            → 本机所有已存在的全局技能目录
#   --project DIR   → 该项目的 .claude/skills + .agents/skills
#   --target DIR    → 只装这些目录（和 --global / --project 同用则叠加）
collect_targets() {
  local explicit_targets=$([ ${#EXTRA_TARGETS[@]} -gt 0 ] && echo 1 || echo 0)
  if [ "$SCOPE" = "project" ]; then
    project_targets
  elif [ "$explicit_targets" = "0" ] || [ "$FORCE_GLOBAL" = "1" ]; then
    global_targets
  fi
  if [ "$explicit_targets" = "1" ]; then printf '%s\n' "${EXTRA_TARGETS[@]}"; fi
  return 0
}

is_ours_link() {
  [ -L "$1" ] && [ "$(realpath_of "$1")" = "$(realpath_of "$SRC")" ]
}

is_ours_dir() {
  [ -d "$1" ] && [ ! -L "$1" ] && [ -f "$1/SKILL.md" ] &&
    grep -qE "^name:[[:space:]]*${SKILL_NAME}[[:space:]]*$" "$1/SKILL.md"
}

status_of() {
  local dest="$1"
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "未安装"
  elif is_ours_link "$dest"; then
    echo "已安装（软链 → 本仓库）"
  elif [ -L "$dest" ]; then
    echo "已安装（软链 → $(realpath_of "$dest")）"
  elif is_ours_dir "$dest"; then
    echo "已安装（拷贝）"
  else
    echo "已存在同名目录（不归本 skill）"
  fi
}

TARGET_DIRS=()
while IFS= read -r dir; do [ -n "$dir" ] && TARGET_DIRS+=("$dir"); done < <(collect_targets)
[ ${#TARGET_DIRS[@]} -gt 0 ] || die "没找到任何客户端技能目录（可用 --target 手动指定）"

if [ "$LIST_ONLY" = "1" ]; then
  bold "$SKILL_NAME skill 安装状态"
  for dir in "${TARGET_DIRS[@]}"; do
    printf '  %-34s %s\n' "${dir/#$HOME/~}" "$(status_of "$dir/$SKILL_NAME")"
  done
  exit 0
fi

bold "skill 源：$SRC"
bold "安装方式：$([ "$MODE" = "copy" ] && echo "复制" || echo "软链（仓库改动即时生效）")"
printf '目标目录：\n'
for dir in "${TARGET_DIRS[@]}"; do
  info "$dir/$SKILL_NAME —— $(status_of "$dir/$SKILL_NAME")"
done

if [ "$ASSUME_YES" != "1" ]; then
  hint="--yes"
  [ "$MODE" = "copy" ] && hint="--copy --yes"
  [ "$UNINSTALL" = "1" ] && hint="--uninstall --yes"
  printf '\n以上只是预览，确认执行请加参数：\n  bash %s %s\n' "$(basename "$0")" "$hint"
  exit 0
fi

for dir in "${TARGET_DIRS[@]}"; do
  dest="$dir/$SKILL_NAME"

  if [ "$UNINSTALL" = "1" ]; then
    if [ -L "$dest" ]; then
      unlink "$dest" && echo "  已卸载 $dest"
    elif is_ours_dir "$dest"; then
      rm -r "$dest" && echo "  已卸载 $dest"
    else
      echo "  跳过 $dest（不存在，或不是本 skill）"
    fi
    continue
  fi

  if is_ours_link "$dest"; then
    echo "  已是最新软链 $dest"
    continue
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ] || is_ours_dir "$dest"; then
      if [ -L "$dest" ]; then unlink "$dest"; else rm -r "$dest"; fi
    else
      die "$dest 已存在且不像本 skill，未做改动。请自行备份后删除，或用 --target 换个目录"
    fi
  fi

  mkdir -p "$dir"
  if [ "$MODE" = "copy" ]; then
    cp -R "$SRC" "$dest"
    find "$dest" -name .DS_Store -delete 2>/dev/null || true
    echo "  已复制到 $dest"
  else
    ln -s "$SRC" "$dest"
    echo "  已软链 $dest → $SRC"
  fi
done

if [ "$UNINSTALL" = "1" ]; then
  printf '\n卸载完成。\n'
  exit 0
fi

cat <<EOF

完成。Claude Code / Cursor / Codex 只在启动时读技能表，**新开一个会话**才生效。
验证：python3 "$SRC/scripts/search.py" "登录页要个锁"
卸载：bash "$(basename "$0")" --uninstall --yes
EOF
