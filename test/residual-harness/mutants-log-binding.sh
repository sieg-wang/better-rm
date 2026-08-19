#!/bin/bash
# mutants-log-binding.sh — 逐一拆掉日誌綁定的每一個 clause，看整套 suite 抓不抓得到
#
# 驗什麼：`log_file_is_bound()` 有四個 clause，外加一個「日誌路徑被佔用」的判斷。
# 每個 clause 都做一個突變，跑整套 `test-better-rm.sh`，看它會不會紅。
#
# 判定分三種，因為「被抓到」有兩種很不一樣的意思：
#   CAUGHT      有**行為測試**紅了 —— 真的有守衛
#   PIN-ONLY    只有 KNOWN-RESIDUALS.md 那個雙向釘紅了 —— 沒有任何行為測試看得見這個改動
#   NOT-CAUGHT  整套全綠 —— 完全沒有覆蓋
#
#   symlink    刪掉 `[ -L ]`            → CAUGHT
#   regular    刪掉 `[ -f ]`            → CAUGHT（FIFO 測試會卡住而逾時）
#   nlink      link 數判斷改成 true     → CAUGHT
#   occupancy  佔用判斷少掉 `[ -L ]`    → CAUGHT
#   owner      刪掉 `[ -O ]`            → **PIN-ONLY**，這就是 R2
#   trimmed    `[ -f ]` 改成只擋 FIFO   → **NOT-CAUGHT**（半套修法，見下）
#
# ⚠️ owner 那一列印出 PIN-ONLY **是正確結果，而且是 R2 的全部內容**：`[ -O ]` 沒有任何
#    行為測試，而且在無 root 的情況下補不出來。root 擁有的檔案本身**做得出來**
#    （`ln /etc/hosts <0700 state dir>/deletion.log` 回 0），但 hardlink 必然 nlink >= 2，
#    會被 link 數那一條擋下——所以刪掉 `[ -O ]` 之後，同一個 fixture 的輸出逐字相同。
#    （唯一會紅的是雙向釘自己，因為 5e295ef 起釘子會 grep 活碼裡的那一行。所以
#    KNOWN-RESIDUALS.md 裡「刪掉整套照樣全綠」那句話，在 edd22fd 已經**不再逐字成立**：
#    行為覆蓋率仍然是零，但釘子會以「文件與程式碼不同步」的形式紅。）
#    **不要為了讓覆蓋率好看去補一個測不到真實條件的測試。**
#
# ⚠️ trimmed 那一列印出 NOT-CAUGHT 也是正確結果，而且是這次移植量出來的**新發現**：
#    把「必須是一般檔」放寬成「只擋 FIFO」，整套 136 個測試沒有一個會紅。可觀察的
#    差別只有一個——**socket 日誌會被靜默接受**（不再出現拒絕訊息）。用
#    `probe-log-path-variants.sh --brm <trimmed build> socket` 可以直接看到。
#    也就是說：FIFO 那個測試釘住的是「不會卡住」，**不是**「必須是一般檔」。
#
# What it verifies: one mutant per clause, each run against the full core suite, with
# three verdicts — CAUGHT (a behavioural test fails), PIN-ONLY (only the
# KNOWN-RESIDUALS two-way pin fails, i.e. zero behavioural coverage), NOT-CAUGHT.
# `owner` is PIN-ONLY: that is R2 in full. `trimmed` is NOT-CAUGHT: relaxing "must be
# a regular file" to "reject only FIFOs" is invisible to all 136 tests, and its only
# observable effect is that a SOCKET log is silently accepted.
#
# 對應 / maps to: R2（owner 那一列）；其餘是綁定檢查的突變覆蓋率
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/build_mutants.sh
#                     + run_mutant_suites.sh + implementation-evidence/mutate.sh
#                     （三支合一；原版各自複製整個 repo，這裡改成單一副本＋快照還原）
#
# usage: mutants-log-binding.sh [mutant ...]      預設全跑
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo

ALL='symlink regular trimmed nlink occupancy owner'
WANTED=''
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '1,36p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) WANTED="$WANTED $1"; shift ;;
    esac
done
[ -n "$WANTED" ] || WANTED="$ALL"

hs_workspace mutants
W="$HS_WORK/work"
BRM="$W/better-rm"
hs_copy_repo "$W"
hs_snapshot "$W" better-rm

L_SYMLINK='    [ -L "$path" ] && return 1'
L_REGULAR='    [ -f "$path" ] || return 1'
L_OWNER='    [ -O "$path" ] || return 1'
L_NLINK='    [ "$links" = "1" ]'
L_OCCUPANCY='    if { [ -e "$log_file" ] || [ -L "$log_file" ]; } && ! log_file_is_bound "$log_file"; then'

apply_mutant() {
    case "$1" in
        symlink)   hs_del_line "$BRM" "$L_SYMLINK" ;;
        regular)   hs_del_line "$BRM" "$L_REGULAR" ;;
        owner)     hs_del_line "$BRM" "$L_OWNER" ;;
        nlink)     hs_sub_line "$BRM" "$L_NLINK" '    true' ;;
        trimmed)   hs_sub_line "$BRM" "$L_REGULAR" '    [ ! -p "$path" ] || return 1' ;;
        occupancy) hs_sub_line "$BRM" "$L_OCCUPANCY" \
                       '    if [ -e "$log_file" ] && ! log_file_is_bound "$log_file"; then' ;;
        *) hs_die "unknown mutant '$1'" ;;
    esac
}

expectation() {
    case "$1" in
        owner)   printf 'PIN-ONLY' ;;
        trimmed) printf 'NOT-CAUGHT' ;;
        *)       printf 'CAUGHT' ;;
    esac
}

# 「被抓到」要分兩種：真的有行為測試紅了，還是只有那個雙向釘紅了。
# 後者代表行為覆蓋率是零，只是文件與程式碼不同步被抓到而已。
classify() {
    local log="$1" failures pin_failures
    failures=$(hs_strip_ansi < "$log" | grep -c '✗ 失敗:')
    pin_failures=$(hs_strip_ansi < "$log" | grep -c '✗ 失敗: KNOWN-RESIDUALS.md 與程式碼不同步')
    if [ "$failures" -eq 0 ]; then
        printf 'NOT-CAUGHT'
    elif [ "$failures" -eq "$pin_failures" ]; then
        printf 'PIN-ONLY'
    else
        printf 'CAUGHT'
    fi
}

printf '\n'
hs_case 'baseline (unmutated)'
hs_pin "$W"
printf 'total=%s passed=%s failed=%s\n' "${HS_PIN_TOTAL:-?}" "${HS_PIN_PASSED:-?}" "${HS_PIN_FAILED:-?}"
BASELINE_FAILED="${HS_PIN_FAILED:-?}"
if [ "$BASELINE_FAILED" != "0" ]; then
    printf 'WARNING: the unmutated suite is not clean; every verdict below is suspect.\n'
    HS_FAILURES=$((HS_FAILURES + 1))
fi
printf '\n'

for m in $WANTED; do
    want=$(expectation "$m")
    hs_case "mutant: $m  (want $want)"
    apply_mutant "$m"
    if ! hs_assert_changed better-rm || ! hs_assert_parses better-rm; then
        printf '\n'
        hs_restore
        continue
    fi
    hs_pin "$W"
    got=$(classify "$HS_WORK/last-core.log")
    if [ "$got" = "$want" ]; then
        printf '%-10s OK    total=%s failed=%s\n' "$got" "${HS_PIN_TOTAL:-?}" "${HS_PIN_FAILED:-?}"
    else
        printf '%-10s MISS! total=%s failed=%s\n' "$got" "${HS_PIN_TOTAL:-?}" "${HS_PIN_FAILED:-?}"
        HS_FAILURES=$((HS_FAILURES + 1))
    fi
    hs_strip_ansi < "$HS_WORK/last-core.log" | grep '✗ 失敗:' | sed 's/^/       /'
    hs_restore
done

printf '\n'
hs_verify_snapshot || HS_FAILURES=$((HS_FAILURES + 1))
hs_summary
