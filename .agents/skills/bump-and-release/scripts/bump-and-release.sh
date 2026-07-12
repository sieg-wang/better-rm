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
AUTO_RELEASE=0
PUSH=1

show_help() {
  cat <<'EOF'
Usage:
  bump-and-release.sh            自動化完成發佈建議流程（release + 檔案提交/打標籤/推播）
  bump-and-release.sh bump [options] [major|minor|patch]
  bump-and-release.sh bump [options] --to <version>
  bump-and-release.sh release [options]

Options:
  -r, --repo <path>        Git repository root (default: current Git root)
  -n, --dry-run            Show planned actions without writing files
  -a, --apply              Enable potentially destructive actions
  --auto                   Run full release flow automatically (add, commit, tag, push)
  --no-push                Skip push step in auto release flow
  --to <version>           Explicit target version for bump mode (e.g. 1.5.0)
  --skip-changelog         Skip writing an Unreleased changelog entry
  --changelog-note <text>  Changelog entry text (default: "Prepare release <version>")
  --tag-prefix <prefix>    Tag prefix for release (default: v)
  -h, --help               Show this help

Note:
  若未指定 bump 類型，預設使用 patch。
  目前版本直接從 better-rm 取得，避免手動輸入。
  不輸入 mode 時預設執行 release；若當前版本標籤已存在，將停止並要求先 bump。
  不輸入其它參數時，會預設啟用 auto 模式，直接完成發佈流程（不再只是列出建議命令）。

Examples:
  bump-and-release.sh                     # 一鍵走完整發佈流程
  bump-and-release.sh --no-push            # 一鍵走完但不推播
  bump-and-release.sh bump --repo ~/projects/better-rm minor
  bump-and-release.sh bump --repo ~/projects/better-rm
  bump-and-release.sh bump --repo ~/projects/better-rm --to 1.5.0
  bump-and-release.sh release --repo ~/projects/better-rm
  bump-and-release.sh release --repo ~/projects/better-rm --auto --no-push
EOF
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    MODE="release"
    AUTO_RELEASE=1
    APPLY=1
    return
  fi

  if [[ "$1" == -* ]]; then
    MODE="release"
    APPLY=1
  else
    MODE="$1"
    shift
  fi

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
      --auto)
        AUTO_RELEASE=1
        shift
        ;;
      --no-push)
        PUSH=0
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

release_tag_exists() {
  local version="$1"
  local tag="${VERSION_PREFIX}${version}"
  if git -C "$PROJECT" show-ref --verify --quiet "refs/tags/${tag}"; then
    return 0
  fi
  return 1
}

run_release() {
  local version
  version="$(current_version)"
  local tag="${VERSION_PREFIX}${version}"
  local -a release_files=(
    "CHANGELOG.md"
    "better-rm"
    "test-better-rm.sh"
    "install.sh"
    "install-hooks.sh"
    "README.md"
  )
  local changed
  local push_cmd="git -C \"$PROJECT\" push origin HEAD --follow-tags"

  if release_tag_exists "$version"; then
    echo "目前版本 ${version} 已存在標籤 ${tag}，請先執行 bump 後再做 release。"
    exit 2
  fi

  run_release_checks

  changed="$(git -C "$PROJECT" status --short -- "${release_files[@]}" || true)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ -n "$changed" ]]; then
      echo "DRY-RUN: 要新增並提交 release 檔案如下："
      echo "$changed"
      echo "DRY-RUN: git -C \"$PROJECT\" add ${release_files[*]}"
      echo "DRY-RUN: git -C \"$PROJECT\" commit -m \"chore(release): bump to ${version}\""
    else
      echo "DRY-RUN: 目前版本檔案無待提交差異，將直接標記標籤。"
    fi
    echo "DRY-RUN: git -C \"$PROJECT\" tag -a \"${tag}\" -m \"Release ${tag}\""
    if [[ "$PUSH" -eq 1 ]]; then
      echo "DRY-RUN: ${push_cmd}"
    else
      echo "DRY-RUN: 已設定 --no-push，跳過推播。"
    fi
    return 0
  fi

  if [[ "$AUTO_RELEASE" -eq 1 ]]; then
    if [[ -n "$changed" ]]; then
      git -C "$PROJECT" add "${release_files[@]}"
      if ! git -C "$PROJECT" diff --cached --quiet -- "${release_files[@]}"; then
        echo "發現版本相關變更，將自動提交："
        git -C "$PROJECT" commit -m "chore(release): bump to ${version}"
      else
        echo "未偵測到需提交的 release 變更。"
      fi
    else
      echo "未偵測到 release 相關未提交變更，將直接進行打標籤。"
    fi

    git -C "$PROJECT" tag -a "${tag}" -m "Release ${tag}"
    echo "已建立標籤：${tag}"
    if [[ "$PUSH" -eq 1 ]]; then
      echo "開始推播..."
      $push_cmd
    else
      echo "已設定 --no-push，已跳過推播。"
    fi
    return 0
  fi

  echo "版本檢查通過，建議後續指令："
  echo "  git -C \"$PROJECT\" add CHANGELOG.md better-rm test-better-rm.sh install.sh install-hooks.sh README.md"
  echo "  git -C \"$PROJECT\" commit -m \"chore(release): bump to ${version}\""
  echo "  git -C \"$PROJECT\" tag -a ${tag} -m \"Release ${tag}\""
  if [[ "$PUSH" -eq 1 ]]; then
    echo "  git -C \"$PROJECT\" push origin HEAD --follow-tags"
  else
    echo "  git -C \"$PROJECT\" push origin HEAD --follow-tags   # 已設定 --no-push，需手動改執行"
  fi
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
