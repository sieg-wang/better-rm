#!/bin/bash
# pin-comment-forms.sh — 釘子的「程式碼那一半」擋得住哪些改法、擋不住哪些
#
# 驗什麼：這是**已知極限 3** 的可執行版本。釘子的程式碼半邊先濾掉**行首**註解
# （`#` / `//`）再比對，所以「把整行註解掉」那一種會紅（CLOSED-*，這是 5e295ef 補的）。
# 其餘全都還是綠的（OPEN-*，實測非推測）：JS 的 `/* … */`、bash 的 `: <<'EOF'`、
# 字串字面、`if false`/`if (false)` 死碼、**行尾註解**、bash 的 `:` no-op 前綴、
# 以及把整行搬進一個沒人呼叫的函式。
#
# ⚠️ OPEN-* 印出 GREEN **是正確結果**，代表那個洞還開著；哪天有人把它補起來，
#    這裡就會印出 MISS，那正是要知道的事（README 有說明怎麼判讀）。
#    行尾註解那種最危險，因為它同時是「看起來已修好」的形狀：預算被調大了、
#    `node --check` 過、釘子維持綠。
#
# What it verifies: the executable form of stated limit 3. The code half of the pin
# filters LINE-LEADING `#` / `//` before matching, so commenting the pinned line out
# that way is caught (CLOSED-*). Everything else still satisfies both code anchors
# (OPEN-*), measured: a JS `/* … */` block, a bash `: <<'EOF'` block, a string
# literal, `if false` / `if (false)` dead code, a TRAILING comment, a bash `:` no-op
# prefix, and moving the line into an uncalled function.
# ⚠️ OPEN-* printing GREEN is the CORRECT result — it means the hole is still open.
#
# 對應 / maps to: 已知極限 3
# 來源 / ported from: KEEP-better-rm/comment-probe.sh（baseline / CLOSED-* / CTRL-*）；
#                     OPEN-* 在 scratchpad 裡沒有對應腳本，是照 KNOWN-RESIDUALS.md
#                     列舉的形狀新寫的（見 README 的 PORT NOTES 註記）。
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_workspace pin-comment

W="$HS_WORK/work"
BRM="$W/better-rm"
JS="$W/test-hooks.js"
hs_copy_repo "$W"
hs_snapshot "$W" better-rm test-hooks.js

CLAUSE='    [ -O "$path" ] || return 1'
BUDGET='  const budgetMs = 1000;'

printf '\n'
hs_case 'baseline (unmutated)'
hs_pin_report "$W" GREEN

# --- CLOSED：行首註解，5e295ef 之後必須紅 ---------------------------------
hs_case 'CLOSED-1 bash: line-leading # comment'
hs_sub_line "$BRM" "$CLAUSE" '    # [ -O "$path" ] || return 1'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" RED
hs_restore

hs_case 'CLOSED-2 js: line-leading // comment'
hs_sub_line "$JS" "$BUDGET" '  // const budgetMs = 1000;
  const budgetMs = 999999;'
hs_assert_changed test-hooks.js && hs_assert_parses test-hooks.js
hs_pin_report "$W" RED
hs_restore

# --- CTRL：直接刪掉／直接改值，本來就會紅 ---------------------------------
hs_case 'CTRL-1 bash: clause deleted outright'
hs_del_line "$BRM" "$CLAUSE"
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" RED
hs_restore

hs_case 'CTRL-2 js: budget replaced outright'
hs_sub_line "$JS" "$BUDGET" '  const budgetMs = 999999;'
hs_assert_changed test-hooks.js && hs_assert_parses test-hooks.js
hs_pin_report "$W" RED
hs_restore

# --- OPEN：實測仍然綠的形狀（GREEN = 洞還開著 = 預期）----------------------
hs_case 'OPEN-1 bash: TRAILING comment (the dangerous shape)'
hs_sub_line "$BRM" "$CLAUSE" '    :  # removed: [ -O "$path" ] || return 1'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-2 bash: `:` no-op prefix (no comment at all)'
hs_sub_line "$BRM" "$CLAUSE" '    : [ -O "$path" ] || return 1'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-3 bash: line moved into a string literal'
hs_sub_line "$BRM" "$CLAUSE" '    _residual_dead_clause='"'"'[ -O "$path" ] || return 1'"'"''
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-4 bash: if false; then … fi dead code'
hs_sub_line "$BRM" "$CLAUSE" '    if false; then
        [ -O "$path" ] || return 1
    fi'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" GREEN
hs_restore

hs_case "OPEN-5 bash: : <<'EOF' heredoc block"
hs_sub_line "$BRM" "$CLAUSE" '    : <<'"'"'RESIDUAL_DEAD'"'"'
[ -O "$path" ] || return 1
RESIDUAL_DEAD'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-6 bash: moved into an uncalled function'
hs_sub_line "$BRM" "$CLAUSE" '    _residual_never_called() {
        [ -O "$path" ] || return 1
    }'
hs_assert_changed better-rm && hs_assert_parses better-rm
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-7 js: /* … */ block comment'
hs_sub_line "$JS" "$BUDGET" '  /* const budgetMs = 1000; */
  const budgetMs = 999999;'
hs_assert_changed test-hooks.js && hs_assert_parses test-hooks.js
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-8 js: TRAILING comment (budget silently raised)'
hs_sub_line "$JS" "$BUDGET" '  const budgetMs = 9999;  // was: const budgetMs = 1000;'
hs_assert_changed test-hooks.js && hs_assert_parses test-hooks.js
hs_pin_report "$W" GREEN
hs_restore

hs_case 'OPEN-9 js: if (false) { … } dead code'
hs_sub_line "$JS" "$BUDGET" '  if (false) { const budgetMs = 1000; }
  const budgetMs = 999999;'
hs_assert_changed test-hooks.js && hs_assert_parses test-hooks.js
hs_pin_report "$W" GREEN
hs_restore

hs_case 'final (restored — must be GREEN again)'
hs_pin_report "$W" GREEN

printf '\n'
hs_verify_snapshot || HS_FAILURES=$((HS_FAILURES + 1))
hs_summary
