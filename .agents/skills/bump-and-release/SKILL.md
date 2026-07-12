---
name: bump-and-release
description: 自動化 better-rm 的版本提升與發佈前檢核，涵蓋版本字串同步、CHANGELOG 更新、必要測試、並輸出可重複執行的發佈步驟。
---

# bump-and-release

本技能適用於 `better-rm` 專案的版本流程，將版本提升、文件同步、發佈前檢查整合成可重複執行的流程。

## 使用時機

- 要求「minor / patch / major」版本提升。
- 針對新版本產生 `CHANGELOG` 下個版本項目。
- 準備 release 前要跑完整測試並驗證版本一致性。
- 需要列出發佈命令（提交、打標籤、推送）而不立即執行。

## 前置條件

- 目前工作目錄位於 `better-rm` 專案根目錄（或以 `--repo` 指定）。
- 需要安裝 `git`、`bash`、`node`。
- `./test-better-rm.sh`、`./test-hooks.js`、`./test-install-hooks.sh` 可正常執行。

## 主要指令

### 1) 僅做版本更新與變更檔

```bash
./.agents/skills/bump-and-release/scripts/bump-and-release.sh bump --repo /path/to/better-rm <major|minor|patch>
./.agents/skills/bump-and-release/scripts/bump-and-release.sh bump --repo /path/to/better-rm --to 1.5.0
```

- 會更新版本來源與驗證：
  - `better-rm`：`show_version` 顯示字串
  - `test-better-rm.sh`：`--version` 預期字串
  - `install.sh`：安裝指引中的版本字串
  - `install-hooks.sh`：`VERSION=` 字串
  - `README.md`：版本提示字串
- 預設會在 `CHANGELOG.md` 的 `[Unreleased]` 下新增一則「Added」項目，除非傳入 `--skip-changelog`。
- 新版本計算錯誤或已存在於檔案中的版本會直接失敗，避免誤更新。

### 2) 做版本提升並跑發佈前檢核

```bash
./.agents/skills/bump-and-release/scripts/bump-and-release.sh release --repo /path/to/better-rm
```

- 先檢查 `git status` 是否乾淨與目前版本是否正確一致。
- 依序執行：
  - `./test-better-rm.sh`
  - `node ./test-hooks.js`
  - `./test-install-hooks.sh`
- 列出推薦發佈命令（包含 `git commit`、`git tag`、`git push`），不會預設直接推播。
- 可用 `--apply` 在執行前加上 `bump` 動作，或搭配 `--dry-run` 僅檢查流程。

## 建議工作流程

1. `bump` 到目標版本並檢查 `git diff`，確認 `README.md`、`CHANGELOG.md`、版本輸出一致。
2. `release --repo <repo> --apply --version <new_version>` 或由外部流程輸入變更訊息後提交。
3. 如需直接打 tag，執行輸出的 `git tag` 指令；發佈前再次檢查 `ci-release.yml` 是否無需額外修正。

## 參考資源

- 版本字串與更新目標：[`references/version-targets.md`](references/version-targets.md)

## 注意事項

- `ci-release.yml` 主要打包整個 git tree，不會逐一列舉要附加的發佈資產；此技能不修改 workflow。
- 版本字串的單位來源不採用 `package.json`，而是由 `better-rm` 腳本輸出與 `install-hooks.sh` 版本變數為準。
