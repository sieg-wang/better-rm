#!/usr/bin/env bash
# shellcheck shell=bash
# Bump version and run release checks for the better-rm project.

set -euo pipefail

PROJECT=""
MODE=""
BUMP_MODE="patch"
BUMP_MODE_EXPLICIT=0
TARGET_VERSION=""
CHANGELOG_NOTE=""
DRY_RUN=0
APPLY=0
VERSION_PREFIX="v"
SKIP_CHANGELOG=0

show_help() {
  cat <<'EOF'
Usage:
  bump-and-release.sh bump [options] [major|minor|patch]
  bump-and-release.sh bump [options] --to <version>
  bump-and-release.sh release [options]

Options:
  -r, --repo <path>        Git repository root (default: current Git root)
  -n, --dry-run            Show planned actions without writing files
  -a, --apply              Enable potentially destructive actions
  --to <version>           Explicit target version for bump mode (e.g. 1.5.0)
  --skip-changelog         Skip writing an Unreleased changelog entry
  --changelog-note <text>  Changelog entry text (default: "Prepare release <version>")
  --tag-prefix <prefix>    Tag prefix for release (default: v)
  -h, --help               Show this help

Note:
  若未指定 bump 類型，預設使用 patch。
  目前版本直接從 better-rm 取得，避免手動輸入。

Examples:
  bump-and-release.sh bump --repo ~/projects/better-rm minor
  bump-and-release.sh bump --repo ~/projects/better-rm
  bump-and-release.sh bump --repo ~/projects/better-rm --to 1.5.0
  bump-and-release.sh release --repo ~/projects/better-rm
EOF
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    show_help
    exit 2
  fi

  MODE="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--repo)
        PROJECT="$2"
        shift 2
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -a|--apply)
        APPLY=1
        shift
        ;;
      --skip-changelog)
        SKIP_CHANGELOG=1
        shift
        ;;
      --changelog-note)
        CHANGELOG_NOTE="$2"
        shift 2
        ;;
      --tag-prefix)
        VERSION_PREFIX="$2"
        shift 2
        ;;
      --to)
        TARGET_VERSION="$2"
        shift 2
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      major|minor|patch)
        if [[ "$BUMP_MODE_EXPLICIT" -eq 1 ]]; then
          echo "Duplicate bump mode: $1" >&2
          exit 2
        fi
        BUMP_MODE_EXPLICIT=1
        BUMP_MODE="$1"
        shift
        ;;
      *)
        echo "未知參數：$1" >&2
        exit 2
        ;;
    esac
  done
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少指令：$1" >&2
    exit 2
  }
}

require_repo() {
  if [[ -z "$PROJECT" ]]; then
    PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  else
    PROJECT="$(cd "$PROJECT" && pwd)"
  fi
  if [[ -z "$PROJECT" ]]; then
    echo "請在 Git repository 中執行，或透過 --repo 指定專案路徑" >&2
    exit 2
  fi
  if ! git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "不是有效的 Git 專案：$PROJECT" >&2
    exit 2
  fi
}

current_version() {
  local file="$PROJECT/better-rm"
  local version
  version="$(grep -m1 -E 'better-rm [0-9]+\.[0-9]+\.[0-9]+' "$file" | sed -E 's/.*better-rm ([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true)"
  if [[ -z "$version" ]]; then
    echo "無法在 better-rm 讀取目前版本" >&2
    exit 2
  fi
  echo "$version"
}

validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "版本格式必須為 x.y.z：$1" >&2
    exit 2
  }
}

next_version() {
  local current="$1"
  local mode="$2"
  IFS='.' read -r major minor patch <<< "$current"
  case "$mode" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "未知 bump 類型：$mode" >&2
      exit 2
      ;;
  esac
  echo "${major}.${minor}.${patch}"
}

replace_version() {
  local file="$1"
  local old_version="$2"
  local new_version="$3"

  if [[ ! -f "$file" ]]; then
    echo "缺少檔案：$file" >&2
    exit 2
  fi

  case "$file" in
    *better-rm)
      perl -0pi -e "s/echo \\\"better-rm ${old_version}\\\"/echo \\\"better-rm ${new_version}\\\"/" "$file"
      ;;
    *test-better-rm.sh)
      perl -0pi -e "s/better-rm ${old_version}/better-rm ${new_version}/g" "$file"
      ;;
    *install.sh|*README.md)
      perl -0pi -e "s/better-rm ${old_version}/better-rm ${new_version}/g" "$file"
      ;;
    *install-hooks.sh)
      perl -0pi -e "s/(VERSION=\\\")${old_version}(\\\")/\$1${new_version}\$2/" "$file"
      ;;
    *)
      perl -0pi -e "s/${old_version}/${new_version}/g" "$file"
      ;;
  esac
}

update_changelog() {
  local version="$1"
  local note="$2"
  local file="$PROJECT/CHANGELOG.md"
  if ! grep -Fq "## [Unreleased]" "$file"; then
    echo "未找到 Unreleased 段落，更新失敗" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  if ! awk -v v="$version" -v n="$note" '
    $0 == "## [Unreleased]" {
      print;
      print "";
      print "### Added";
      print "- " v ": " n;
      print "";
      inserted = 1;
      next;
    }
    { print; }
    END {
      if (!inserted) { exit 1; }
    }
  ' "$file" > "$tmp"; then
    echo "更新 CHANGELOG 失敗，未找到插入點" >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$file"
}

run_bump() {
  local current next
  current="$(current_version)"
  if [[ -n "$TARGET_VERSION" ]]; then
    validate_version "$TARGET_VERSION"
    next="$TARGET_VERSION"
  elif [[ -n "$BUMP_MODE" ]]; then
    next="$(next_version "$current" "$BUMP_MODE")"
  else
    echo "請指定 bump 類型或 --to 版本" >&2
    exit 2
  fi

  if [[ "$current" == "$next" ]]; then
    echo "目前版本已是目標版本：$next"
    exit 2
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: ${current} -> ${next}"
    return 0
  fi

  for file in \
    "$PROJECT/better-rm" \
    "$PROJECT/test-better-rm.sh" \
    "$PROJECT/install.sh" \
    "$PROJECT/install-hooks.sh" \
    "$PROJECT/README.md"; do
    replace_version "$file" "$current" "$next"
  done

  if [[ "$SKIP_CHANGELOG" -eq 0 ]]; then
    local note="${CHANGELOG_NOTE:-Prepare release $next}"
    update_changelog "$next" "$note"
  fi

  if ! grep -q "better-rm $next" "$PROJECT/better-rm"; then
    echo "版本更新失敗，請檢查檔案寫入" >&2
    exit 2
  fi
  echo "版本已更新：${current} -> ${next}"
}

run_release_checks() {
  require_command node
  if [[ -n "$(git -C "$PROJECT" status --porcelain)" ]]; then
    echo "發現未提交變更，建議先完成版本 bump 與暫存清單" >&2
    if [[ "$APPLY" -ne 1 ]]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN 模式：仍然會列出建議指令，但實際發佈前請先確保工作目錄乾淨" >&2
        return 0
      fi
      exit 2
    fi
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: 跳過測試執行"
    return 0
  fi

  (
    cd "$PROJECT"
    set -x
    ./test-better-rm.sh
    node ./test-hooks.js
    ./test-install-hooks.sh
  )
}

run_release() {
  run_release_checks
  local version
  version="$(current_version)"
  local tag="${VERSION_PREFIX}${version}"

  echo "版本檢查通過，建議後續指令："
  echo "  git -C \"$PROJECT\" add CHANGELOG.md better-rm test-better-rm.sh install.sh install-hooks.sh README.md"
  echo "  git -C \"$PROJECT\" commit -m \"chore(release): bump to ${version}\""
  echo "  git -C \"$PROJECT\" tag -a ${tag} -m \"Release ${tag}\""
  echo "  git -C \"$PROJECT\" push origin HEAD --follow-tags"
  echo "如不直接提交，請先確認已在 git diff 中檢視版本同步情形。"
}

main() {
  parse_args "$@"
  require_repo

  case "$MODE" in
    bump)
      run_bump
      ;;
    release)
      run_release
      ;;
    *)
      echo "不支援的模式：$MODE" >&2
      show_help
      exit 2
      ;;
  esac
}

main "$@"
