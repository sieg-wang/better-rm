#!/bin/bash
# pin-nul-evasion.sh — 精確計數的 BSD-only 繞法：NUL 位元組 ＋ LC_ALL=C
#
# 驗什麼：這是**已知極限 4** 的可執行版本。BSD `grep -o` 碰到含 NUL 的檔案會印一行
# `Binary file … matches`，於是 `wc -l` 永遠讀成 1，不論實際有幾份 anchor 拷貝。
# 完整攻擊 = 刪掉整個 R1 段落 ＋ 留兩個孤立 token ＋ 種一個 NUL：在 `LC_ALL=C` 下
# 整套 suite 全綠（釘子看不見自己已經被繞過）。
# 兩個條件缺一不可，所以這裡同時跑兩個控制組：無 NUL → 紅；有 NUL 但 UTF-8 locale → 紅。
#
# ⚠️ ATTACK 那一列印出 GREEN **是正確結果**，代表繞法仍然成立。
# ⚠️ 本機是 BSD grep。CI 是 ubuntu（GNU grep），**那一側是推論不是實測**——這支腳本
#    在 Linux 上跑出什麼，就是那一側的第一手資料，請把結果寫回 KNOWN-RESIDUALS.md。
#
# What it verifies: the executable form of stated limit 4. BSD `grep -o` prints a
# single `Binary file … matches` line for a file containing a NUL, so `wc -l` reads 1
# no matter how many copies exist. The full attack (delete the R1 section, leave two
# stray tokens, plant one NUL) is green under LC_ALL=C. Both controls must be RED.
# The GNU-grep side is INFERRED, not measured — running this on Linux settles it.
#
# 對應 / maps to: 已知極限 4
# 來源 / ported from: 無。scratchpad 裡沒有這支；當時的量測是即席做的，這裡補寫成
#                     可重跑的形式（見 README 的 PORT NOTES 註記）。
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_workspace pin-nul

W="$HS_WORK/work"
DOC="$W/KNOWN-RESIDUALS.md"
hs_copy_repo "$W"
hs_snapshot "$W" KNOWN-RESIDUALS.md

# 攻擊組裝：刪掉 R1 整段，再補兩個孤立 token（釘子的字串存在檢查照樣命中）。
build_attack() {
    perl -0pi -e 's{\n## R1 .*?(?=\n## R2 )}{\n}s' "$DOC"
    printf '\n<!-- O_NOFOLLOW -->\n<!-- O_NOFOLLOW -->\n' >> "$DOC"
}

plant_nul() {
    perl -e 'print "\0"' >> "$DOC"
}

report_counter() {
    local locale="$1"
    printf '  LC_ALL=%-12s grep -o | wc -l  =>  %s\n' "$locale" \
        "$(LC_ALL=$locale grep -o -- 'O_NOFOLLOW' "$DOC" 2>/dev/null | wc -l | tr -d '[:space:]')"
}

# 「git 會把它顯示成 binary，review 時很難不注意」是這個極限唯一的實務緩解措施。
# 這裡不採信、直接量：git 只看**前 8000 bytes**，所以 NUL 種在檔尾時 git 照樣把它
# 當成純文字，緩解措施在那個位置**不成立**。numstat 印 `-  -` 才是 binary。
# The stated mitigation is that git shows the file as binary. Measured, not assumed:
# git only inspects the FIRST 8000 BYTES, so a NUL planted past that point leaves an
# ordinary text diff. `git diff --numstat` prints `-  -` only when git says binary.
git_visibility() {
    local label="$1" numstat
    numstat=$(cd "$W" && git diff --numstat -- KNOWN-RESIDUALS.md 2>/dev/null | head -1)
    case "$numstat" in
        -*) printf '  git sees %-28s BINARY   (%s)\n' "$label" "$numstat" ;;
        '') printf '  git sees %-28s (no diff)\n' "$label" ;;
        *)  printf '  git sees %-28s TEXT     (%s)  <- mitigation does NOT hold here\n' \
                "$label" "$numstat" ;;
    esac
}

printf '\ngrep flavour on this machine: %s\n' \
    "$(grep --version 2>/dev/null | head -1 || echo 'unknown (BSD grep has no --version)')"
printf '\n'

hs_case 'baseline, LC_ALL=C (unmutated)'
HS_LC_ALL=C
hs_pin_report "$W" GREEN

hs_case 'CTRL-1 attack WITHOUT a NUL, LC_ALL=C'
build_attack
hs_assert_changed KNOWN-RESIDUALS.md
HS_LC_ALL=C
hs_pin_report "$W" RED
report_counter C
hs_restore

hs_case 'CTRL-2 attack WITH a NUL, LC_ALL=en_US.UTF-8'
build_attack
plant_nul
hs_assert_changed KNOWN-RESIDUALS.md
HS_LC_ALL=en_US.UTF-8
hs_pin_report "$W" RED
report_counter en_US.UTF-8
hs_restore

hs_case 'ATTACK  attack WITH a NUL, LC_ALL=C  (GREEN = evasion holds)'
build_attack
plant_nul
hs_assert_changed KNOWN-RESIDUALS.md
HS_LC_ALL=C
hs_pin_report "$W" GREEN
report_counter C
printf '  file size = %s bytes; git inspects only the first 8000\n' \
    "$(wc -c < "$DOC" | tr -d '[:space:]')"
git_visibility 'a NUL appended at EOF:'
hs_restore

hs_case 'MITIGATION check: NUL planted inside the first 8000 bytes'
build_attack
perl -0pi -e 's/^/\0/' "$DOC"
printf 'planted\n'
git_visibility 'a NUL near byte 0:'
hs_restore

hs_case 'final (restored — must be GREEN again)'
HS_LC_ALL=C
hs_pin_report "$W" GREEN

printf '\n'
hs_verify_snapshot || HS_FAILURES=$((HS_FAILURES + 1))
hs_summary
