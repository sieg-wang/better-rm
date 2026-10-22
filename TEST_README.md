# Better-RM 測試腳本說明
# Better-RM Test Script Documentation

## 概述 (Overview)

`test-better-rm.sh` 是一個完整的測試腳本，用於驗證 better-rm 的所有功能與特性。

## 使用方式 (Usage)

### 基本執行 (Basic Execution)

```bash
./test-better-rm.sh
```

### 在容器環境中執行 (Run in Container Environment)

```bash
# Docker
docker run -v $(pwd):/app ubuntu:latest bash /app/test-better-rm.sh

# Podman
podman run -v $(pwd):/app:z ubuntu:latest bash /app/test-better-rm.sh
```

## 測試項目 (Test Items)

### 測試 1: 版本與說明資訊
- 測試 `--version` 參數
- 測試 `--help` 參數

### 測試 2: 基本檔案刪除功能
- 刪除單一檔案
- 刪除多個檔案

### 測試 3: 目錄刪除功能
- 遞迴刪除目錄 (-r)
- 刪除空目錄
- 不加 -r 刪除目錄應失敗

### 測試 4: 特殊字元檔名處理
- 檔名含空格
- 檔名含特殊字元
- 中文檔名

### 測試 5: 符號連結處理
- 刪除符號連結（目標檔案應保留）

### 測試 6: 時間戳記與內容 Hash
- 檔名包含時間戳記和 Hash
- 相同檔名但不同內容產生不同 Hash
- 空檔案的 Hash

### 測試 7: 刪除日誌功能
- 日誌檔案自動創建
- 狀態目錄與日誌檔案權限
- 日誌記錄檔案刪除
- 日誌記錄目錄刪除
- 日誌記錄符號連結
- 日誌格式正確
- 日誌目錄不可用時仍完成刪除且不洩漏 Shell 錯誤

### 測試 8: 命令參數選項
- 詳細模式 (-v)
- 強制模式 (-f)
- 組合參數 (-rf)

### 測試 9: 受保護目錄
- 柵欄自我檢查：先對沙箱目錄跑一次 better-rm，PATH 只剩一個目錄，裡面是預設 PATH 上每一個執行檔名的 symlink，全部指向一支記錄名字的 dispatcher。find、xargs、md5sum、sha256sum、mv 這五個柵欄名字一律記錄後以 97 結束、從不執行真工具，而且五個都必須出現；允許清單裡的唯讀小工具（以及只碰得到沙箱 TRASH_DIR／STATE_DIR 的 mkdir、rmdir）照常執行；其餘任何名字一被叫到，自我檢查就失敗。刪除路徑多用一個新工具（例如量空間的 du/df、明確跨裝置複製的 cp/rm），得先把它加進柵欄或允許清單
- Fence self-check: one better-rm run on a sandbox directory with PATH set to a single directory of symlinks, one for every executable name on the default PATH, all pointing at a dispatcher that records the name. The five fenced names (find, xargs, md5sum, sha256sum, mv) are recorded and exit 97 without running the real tool, and all five must appear; allowlisted read-only helpers (plus mkdir and rmdir, which only reach the sandboxed TRASH_DIR/STATE_DIR) run normally; any other name that is invoked fails the self-check. A new tool on the delete path (du/df for a space check, cp/rm for an explicit cross-device copy) has to be fenced or allowlisted first
- 拒絕刪除根目錄 (/)
- 拒絕刪除 /home
- 拒絕刪除 /mnt 與第一層掛載根
- 允許處理 /mnt 掛載根內的一般路徑
- 拒絕刪除 .git 目錄

對真實 /、/home、/mnt 的那幾列都在柵欄後面跑、各有 15 秒上限，而且柵欄紀錄必須是空的；柵欄自我檢查沒過，那幾列就不執行、直接判失敗。refusal 退化時，better-rm 的 find、md5sum 與 mv 打到的是 shim 而不是真的工具（以 root 在容器裡執行時也一樣）；柵欄沒涵蓋的工具則在 15 秒後被終止。
The rows on the real /, /home and /mnt run behind that fence, each bounded at 15 s, and each requires an empty fence log; if the fence self-check fails, those rows are not run and fail instead. With the refusal regressed, better-rm's find, md5sum and mv reach the shims instead of the real tools (under the root docker run above as well), and a tool the fence does not cover is stopped after 15 s.

### 測試 10: 快速連續刪除
- 五個不同檔案並行刪除：每一個都在垃圾桶裡留下恰好一筆（不多不少）。檔名各不相同，所以這一列不會產生時間戳記碰撞
- 同路徑、同內容、同時間戳記的碰撞：以固定時間戳記的 `date` shim 重現，既有的垃圾桶項目與晚到的項目都不得被覆蓋

### 測試 11: 垃圾桶路徑結構保留
- 深層目錄結構保留

### 測試 12: 自訂垃圾桶目錄
- 使用自訂 TRASH_DIR 環境變數
- 使用自訂 BETTER_RM_STATE_DIR 環境變數
- 使用 XDG_STATE_HOME 與無效相對路徑回退

### 測試 13: 還原功能
- 基本還原
- 已移出垃圾桶項目的再次還原
- 同名檔案覆蓋確認
- `-f` 強制覆蓋
- 同名提示回答 `n` 或沒有回答（stdin 是 `/dev/null`）時什麼都不動，結束碼 0
- 以刪除時用的路徑寫法還原（`../`、結尾斜線、經過符號連結的 parent），對不到時提示用名稱還原會拿到哪一筆
- 新日誌沒有符合項目時回退舊版垃圾桶日誌

### 測試 16: README 的垃圾桶清理函式
- 從 README.md 抽出 `better_rm_purge`，在測試自己的暫存目錄裡造的垃圾桶上跑（`TRASH_DIR` 與 `HOME` 都指進那裡）：清單與 `--delete` 只碰兩筆刪除時間在 2025 年的項目；剛刪的項目（包括長得像項目的目錄裡、舊項目的鏡像目錄裡的）與最上層的 Finder 式項目都不碰，兩個長得像項目的目錄被點名略過

## 測試結果 (Test Results)

測試腳本會顯示：
- 總測試數
- 通過測試數
- 失敗測試數

如果所有測試通過，返回 exit code 0；否則返回 exit code 1。

## 環境需求 (Requirements)

- Bash 3.2+（macOS 內建的 /bin/bash 3.2.57 即可；腳本以 `#!/bin/bash` 執行）
- 基本 Unix 工具（find, grep, awk, wc 等）
- md5sum 或 sha256sum

## 測試目錄 (Test Directories)

測試腳本使用的臨時目錄都以這一次執行的識別碼結尾（`<id>` 是 `BETTER_RM_TEST_RUN_ID`，未設定時是腳本的 PID），所以同時跑的兩次測試不會互相刪掉對方的 fixture：
- `/tmp/better-rm-test-trash.<id>` - 測試用垃圾桶目錄
- `/tmp/better-rm-test-state.<id>` - 測試用狀態與日誌目錄
- `/tmp/better-rm-test-work.<id>` - 測試工作目錄
- `/tmp/better-rm-test-state-blocker.<id>` - 測試「狀態目錄不可用」的一般檔案
- `/tmp/custom-trash-test.<id>`、`/tmp/custom-better-rm-state-test.<id>`、`/tmp/custom-xdg-state-test.<id>`、`/tmp/better-rm-state-fallback-home.<id>` - 測試 12 的自訂位置

唯一刻意不帶識別碼的是測試 0 的 `/tmp/better-rm-test-work`：它模擬「舊版寫死名稱的另一次執行」，裡面只放帶識別碼的 canary 檔，清理時只刪自己的 canary，目錄只有在是這一次建立且已清空時才移除。

測試完成後會自動清理。

## 故障排除 (Troubleshooting)

### 測試失敗
如果某個測試失敗，檢查：
1. better-rm 腳本是否有執行權限
2. 是否有足夠的磁碟空間
3. 是否有必要的系統工具（md5sum, find 等）

### 容器環境注意事項
在容器中執行時：
1. 確保掛載的目錄有執行權限
2. 容器需要有 bash 環境
3. 需要安裝 coreutils 套件

## 範例輸出 (Example Output)

```
Better-RM 完整測試套件
Better-RM Comprehensive Test Suite

測試腳本: /path/to/better-rm
垃圾桶目錄: /tmp/better-rm-test-trash
工作目錄: /tmp/better-rm-test-work

========================================
測試 1: 版本與說明資訊
========================================
[測試 0] 測試 --version 參數
✓ 通過: --version 顯示正確版本
...

========================================
測試結果統計 (Test Results Summary)
========================================

總測試數 (Total Tests): 28
通過測試 (Passed): 28
失敗測試 (Failed): 0

✓ 所有測試通過！(All tests passed!)
```

## 貢獻 (Contributing)

如需添加新的測試項目：
1. 在適當的測試區塊中添加新的測試函數
2. 使用 `test_item` 描述測試項目
3. 使用 `test_pass` 或 `test_fail` 記錄結果
4. 確保測試結束後清理所有臨時檔案

## 授權 (License)

與 better-rm 專案相同的授權條款。
