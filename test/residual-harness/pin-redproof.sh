#!/bin/bash
# pin-redproof.sh — KNOWN-RESIDUALS.md「雙向釘」的 red-proof（2026-08-19 原始量測的移植）
#
# 驗什麼：`test-better-rm.sh` 裡那條把 R1/R2/R3 釘住的測試，兩個方向都真的會紅。
#   文字面 —— 三個 anchor 各自被改寫、以及整份文件被刪掉。
#   程式碼面 —— [-O] clause 被拿掉、budgetMs 被改成不看牆鐘、log_file_is_bound 被改名。
# 六個突變加上「檔案整份刪掉」，每一個都必須讓那條測試變紅；baseline 與還原後必須綠。
#
# What it verifies: the two-way pin in test-better-rm.sh fails in BOTH directions —
# three prose anchors reworded, the doc deleted, and the three code facts changed.
# Every mutation must turn the pin RED; baseline and the restored run must be GREEN.
#
# 對應 / maps to: R1、R2、R3（釘子本身，不是殘留本身）
# 來源 / ported from: scratchpad KEEP-better-rm/redproof.sh
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_workspace pin-redproof

W="$HS_WORK/work"
hs_copy_repo "$W"
hs_snapshot "$W" KNOWN-RESIDUALS.md better-rm test-hooks.js
printf '\n'

hs_case 'baseline (unmutated)'
hs_pin_report "$W" GREEN

hs_case 'M1 doc: R1 fix-direction token mangled'
hs_sub_str "$W/KNOWN-RESIDUALS.md" 'O_NOFOLLOW' 'XNOFOLLOWX'
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'M2 doc: R2 untestability reason reworded'
hs_sub_str "$W/KNOWN-RESIDUALS.md" '無法在無 root 的情況下測試' '可以測試'
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'M3 doc: R3 symmetry conclusion reworded'
hs_sub_str "$W/KNOWN-RESIDUALS.md" '兩邊都紅' '單邊紅'
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'M4 doc: KNOWN-RESIDUALS.md deleted entirely'
"$HS_RM" -f "$W/KNOWN-RESIDUALS.md"
hs_pin_report "$W" RED
hs_restore

hs_case 'M5 code: the [-O] ownership clause removed'
hs_sub_line "$W/better-rm" '    [ -O "$path" ] || return 1' '    : removed'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" RED
hs_restore

hs_case 'M6 code: budgetMs made load-insensitive'
hs_sub_str "$W/test-hooks.js" 'const budgetMs = 1000;' 'const budgetMs = Number.MAX_SAFE_INTEGER;'
hs_assert_changed test-hooks.js && hs_assert_parses test-hooks.js
hs_pin_report "$W" RED
hs_restore

hs_case 'M7 code: log_file_is_bound renamed (the fd rework)'
hs_sub_str "$W/better-rm" 'log_file_is_bound' 'log_fd_is_bound'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" RED
hs_restore

hs_case 'final (restored — must be GREEN again)'
hs_pin_report "$W" GREEN

printf '\n'
hs_verify_snapshot || HS_FAILURES=$((HS_FAILURES + 1))
hs_summary
