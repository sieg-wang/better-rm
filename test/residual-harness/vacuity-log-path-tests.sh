#!/bin/bash
# vacuity-log-path-tests.sh — 那兩個新測試的斷言是真的綁著，還是永遠不會紅
#
# 驗什麼：FIFO 與「斷掉的 symlink」兩個測試各自先把 fixture 種好，再斷言 better-rm
# 拒絕記錄。**空洞測試**的形狀是：斷言鬆到 fixture 換成一個普通檔也照樣過。所以這裡
# 只破壞測試**自己的前提**（`mkfifo` → `touch`、`ln -s` → `touch`），better-rm 完全
# 不動。前提沒了，那兩列就必須紅——因為普通自有檔是合法日誌，拒絕訊息不會出現。
# 兩列都紅 = 斷言真的綁著。任何一列還綠 = 那個測試量不到它宣稱在量的東西。
#
# What it verifies: that the two log-path tests are not vacuous. It sabotages only
# each test's OWN precondition (a plain file instead of a FIFO / instead of a dangling
# symlink) and leaves better-rm untouched. A plain self-owned file is a legal log, so
# the refusal never fires and both rows MUST go red. A row that stays green is a test
# that cannot measure what it claims to measure.
#
# 對應 / maps to: 不對應 R1–R3；這是 ca02eca 兩個新測試的非空洞性證據
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/vacuity.sh
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_workspace vacuity

W="$HS_WORK/work"
SUITE="$W/test-better-rm.sh"
hs_copy_repo "$W"
hs_snapshot "$W" test-better-rm.sh

printf '\n'
hs_case 'baseline (unsabotaged)'
hs_pin "$W"
printf 'total=%s passed=%s failed=%s\n' "${HS_PIN_TOTAL:-?}" "${HS_PIN_PASSED:-?}" "${HS_PIN_FAILED:-?}"
if [ "${HS_PIN_FAILED:-1}" != "0" ]; then
    printf 'WARNING: the unsabotaged suite is not clean; the verdict below is suspect.\n'
    HS_FAILURES=$((HS_FAILURES + 1))
fi

hs_sub_line "$SUITE" 'mkfifo "$fifo_log_state/deletion.log"' \
                     'touch "$fifo_log_state/deletion.log"'
hs_sub_line "$SUITE" 'ln -s "$dangling_log_target" "$dangling_log_state/deletion.log"' \
                     'touch "$dangling_log_state/deletion.log"'

printf '\nsabotage applied (fixtures only, better-rm untouched):\n'
( cd "$W" && git --no-pager diff -- test-better-rm.sh 2>/dev/null |
    grep -E '^[-+][^-+]' | sed 's/^/  /' )
printf '\n'

if ! hs_assert_changed test-better-rm.sh || ! hs_assert_parses test-better-rm.sh; then
    printf '\n'
    hs_summary
    exit 1
fi

hs_case 'sabotaged (both rows must now be RED)'
hs_pin "$W"
printf 'total=%s passed=%s failed=%s\n' "${HS_PIN_TOTAL:-?}" "${HS_PIN_PASSED:-?}" "${HS_PIN_FAILED:-?}"
hs_strip_ansi < "$HS_WORK/last-core.log" | grep '✗ 失敗:' | sed 's/^/   /'

if [ "${HS_PIN_FAILED:-0}" = "2" ]; then
    printf '\nBoth assertions bind: neither test can pass without its own fixture.\n'
else
    printf '\nEXPECTED exactly 2 failures, got %s — at least one assertion is vacuous\n' \
        "${HS_PIN_FAILED:-?}"
    printf 'or a third test depends on these fixtures. Read the failure list above.\n'
    HS_FAILURES=$((HS_FAILURES + 1))
fi

hs_restore
printf '\n'
hs_verify_snapshot || HS_FAILURES=$((HS_FAILURES + 1))
hs_summary
