# 版本更新目標檔案

版本提升時需要同步的版本字串位置如下：

- `better-rm`
  - `show_version` 函式內 `echo "better-rm X.Y.Z"`
- `test-better-rm.sh`
  - `grep -q "better-rm X.Y.Z"` 斷言
- `install.sh`
  - 安裝完成驗證訊息中的 `better-rm X.Y.Z`
- `install-hooks.sh`
  - `VERSION="X.Y.Z"` 變數
- `README.md`
  - `rm --version` 預期輸出文字

不建議直接以全域搜尋 `X.Y.Z` 全取代整個專案，需限定在上述檔案與欄位，避免改到歷史版本紀錄文字。

