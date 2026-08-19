#!/bin/bash
# pin-anchor-uniqueness.sh — 「每個 anchor 恰好出現一次」是不是真的紅得起來
#
# 驗什麼：這是**已知極限 2** 的可執行版本。釘子看得到字串、看不到位置，所以只要
# 文件裡多出第二份 anchor 字面拷貝，整個 R 段落被刪掉時測試照樣綠（2026-08-19 的
# 揭露段落自己就犯過這個錯，見 commit a37d49b）。這支腳本兩邊都量：
#   DUP-* 種入第二份拷貝（自成一行／程式碼圍籬內／同一行／接在既有句尾／同行三份），
#         每一種都必須紅；
#   DEL-* 把整個 R1/R2/R3 段落或 R1 的修法段落刪掉，每一種也都必須紅。
# 另外示範計數陷阱本身：`grep -c` 數的是「有命中的行數」，同一行放兩次照樣回 1
# （commit 8ca60c5 修的就是這個），所以釘子改用 `grep -o | wc -l | tr -d`。
#
# What it verifies: the executable form of stated limit 2. The pin sees strings, not
# positions, so a second literal copy of an anchor makes deleting the whole section
# invisible. DUP-* plant a second copy (own line / inside a code fence / same line /
# appended to an existing line / three on one line) — each must go RED. DEL-* remove
# whole sections — each must go RED. It also demonstrates the counting trap itself:
# `grep -c` counts matching LINES, so two on one line still reads as 1.
#
# 對應 / maps to: 已知極限 2（+ 極限 4 的計數半邊）
# 來源 / ported from: KEEP-better-rm/uniqueness.sh + sameline.sh + anchor-uniqueness.sh
#                     （三支重疊極大，這裡合成一支；見 README 的 DEDUPED）
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_workspace pin-anchor-uniq

W="$HS_WORK/work"
DOC="$W/KNOWN-RESIDUALS.md"
hs_copy_repo "$W"
hs_snapshot "$W" KNOWN-RESIDUALS.md

ANCHOR_R1='O_NOFOLLOW'
ANCHOR_R2='無法在無 root 的情況下測試'
ANCHOR_R3='兩邊都紅'

count_c()  { grep -c -- "$1" "$2"; }
count_o()  { grep -o -- "$1" "$2" | wc -l | tr -d '[:space:]'; }

show_counts() {
    local label="$1" a
    printf '%s\n' "$label"
    for a in "$ANCHOR_R1" "$ANCHOR_R2" "$ANCHOR_R3"; do
        printf '  %-34s grep -c=%s   grep -o|wc -l=%s\n' \
            "$a" "$(count_c "$a" "$DOC")" "$(count_o "$a" "$DOC")"
    done
}

printf '\n'
show_counts 'anchor counts at HEAD (each must read exactly 1):'

# 計數陷阱的現場示範：同一行放兩次，grep -c 仍然回 1。
printf '\nthe counting trap, demonstrated (same-line duplicate planted):\n'
printf '\n%s %s\n' "$ANCHOR_R1" "$ANCHOR_R1" >> "$DOC"
printf '  %-34s grep -c=%s   grep -o|wc -l=%s   <- -c is the wrong counter\n' \
    "$ANCHOR_R1" "$(count_c "$ANCHOR_R1" "$DOC")" "$(count_o "$ANCHOR_R1" "$DOC")"
hs_restore
printf '\n'

hs_case 'baseline (unmutated)'
hs_pin_report "$W" GREEN

hs_case 'DUP-1 second copy on its own line'
printf '\n<!-- %s -->\n' "$ANCHOR_R1" >> "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'DUP-2 second copy inside a code fence'
printf '\n```\n%s\n```\n' "$ANCHOR_R1" >> "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

for a in "$ANCHOR_R1" "$ANCHOR_R3" "$ANCHOR_R2"; do
    hs_case "DUP-3 same-line duplicate [$a]"
    printf '\n%s %s\n' "$a" "$a" >> "$DOC"
    hs_assert_changed KNOWN-RESIDUALS.md
    hs_pin_report "$W" RED
    hs_restore
done

hs_case 'DUP-4 appended to an existing prose line'
perl -0pi -e 's{(\n\*\*要修的話，正確方向是\*\*[^\n]*)}{$1 O_NOFOLLOW}' "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'DUP-5 three occurrences on one line'
printf '\n%s %s %s\n' "$ANCHOR_R1" "$ANCHOR_R1" "$ANCHOR_R1" >> "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'DEL-1 whole R1 section removed'
perl -0pi -e 's{\n## R1 .*?(?=\n## R2 )}{\n}s' "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'DEL-2 whole R2 section removed'
perl -0pi -e 's{\n## R2 .*?(?=\n## R3 )}{\n}s' "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'DEL-3 whole R3 section removed'
perl -0pi -e 's{\n## R3 .*}{\n}s' "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'DEL-4 only R1 fix-direction paragraph removed'
perl -0pi -e 's{\n\*\*要修的話，正確方向是\*\*.*?\n\n}{\n}s' "$DOC"
hs_assert_changed KNOWN-RESIDUALS.md
hs_pin_report "$W" RED
hs_restore

hs_case 'final (restored — must be GREEN again)'
hs_pin_report "$W" GREEN

printf '\n'
hs_verify_snapshot || HS_FAILURES=$((HS_FAILURES + 1))

# 計數器本身的可攜性：`tr -d` 是必要的（BSD wc -l 會補前導空白），而 locale 會不會
# 讓 UTF-8 anchor 數錯也一起量。三個都必須印 1。
printf '\nportability of the exactly-once counter (each must print 1):\n'
for L in C en_US.UTF-8 zh_TW.UTF-8; do
    printf '  LC_ALL=%-12s %s\n' "$L" \
        "$(LC_ALL=$L grep -o -- "$ANCHOR_R3" "$DOC" | wc -l | tr -d '[:space:]')"
done

# 這套 suite 必須在 stock /bin/bash 3.2.57 下也綠（CI 是 ubuntu，本機是 macOS）。
printf '\nstock /bin/bash run of the core suite: '
if hs_isolated "$W" /bin/bash ./test-better-rm.sh > "$HS_WORK/stockbash.log" 2>&1; then
    printf 'rc=0 GREEN (%s)\n' \
        "$(hs_strip_ansi < "$HS_WORK/stockbash.log" | grep -E '總測試數|通過測試|失敗測試' | tr '\n' ' ')"
else
    printf 'rc!=0\n'
    hs_strip_ansi < "$HS_WORK/stockbash.log" | grep -E '總測試數|通過測試|失敗測試|✗' | sed 's/^/    /'
    HS_FAILURES=$((HS_FAILURES + 1))
fi

hs_summary
