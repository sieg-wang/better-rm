#!/bin/bash
# probe-log-path-variants.sh — 在刪除日誌路徑上種各種物件，看 better-rm 怎麼反應
#
# 驗什麼：`log_file_is_bound()` 的四個 clause 面對七種「日誌路徑不是一個正常自有
# 一般檔」的情況，實際行為是什麼。這是 88e6611（跟著預先種好的連結寫、記錄可執行）
# 與 ca02eca 兩個修復的直接證據來源，也是 R2 結論的來源之一：
#   hardlink fixture 拿掉 `[ -O ]` 之後由 link 數那一條擋下，輸出逐字相同。
#
# 每一個 variant 都在自己的隔離工作區裡跑：HOME / TRASH_DIR / BETTER_RM_STATE_DIR /
# XDG_STATE_HOME / TMPDIR / cwd 全部指進 mktemp 工作區，真實使用者檔案碰不到。
#
# What it verifies: how better-rm behaves when the deletion-log path is not an
# ordinary self-owned regular file — seven planted shapes. This is the evidence
# behind the 88e6611 and ca02eca fixes, and one source of the R2 conclusion
# (the hardlink fixture is stopped by the link-count clause once `[ -O ]` is gone,
# so its output is byte-identical either way).
#
# 對應 / maps to: R2（hardlink 那一列）；其餘是修復本身的回歸探針
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/probe_variants.sh
#                     + probe_dangling.sh + probe_fifo.sh
#                     + implementation-evidence/probe-dangling.sh + probe-fifo.sh
#                     （五支合一；見 README 的 DEDUPED）
#
# usage: probe-log-path-variants.sh [--brm <path>] [variant ...]
#        variant ∈ dangling fifo socket dir chain chain_live hardlink   (預設全跑)
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_require_timeout

BRM="$HS_REPO/better-rm"
ALL_VARIANTS='dangling fifo socket dir chain chain_live hardlink'
VARIANTS=''

while [ $# -gt 0 ]; do
    case "$1" in
        --brm) BRM="$2"; shift 2 ;;
        -h|--help) sed -n '1,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) VARIANTS="$VARIANTS $1"; shift ;;
    esac
done
[ -n "$VARIANTS" ] || VARIANTS="$ALL_VARIANTS"
[ -x "$BRM" ] || hs_die "'$BRM' is not executable"

hs_workspace probe-variants
printf 'under test : %s\n\n' "$BRM"

DEFECTS=0

plant() {
    local variant="$1" log="$2" target="$3" state="$4"
    case "$variant" in
        dangling)   ln -s "$target" "$log" ;;
        fifo)       mkfifo "$log" ;;
        dir)        mkdir "$log" ;;
        socket)     # AF_UNIX 路徑在 macOS 上限 104 bytes，所以 chdir 之後用相對路徑 bind
                    perl -e 'use Socket; chdir($ARGV[0]) or die "chdir: $!";
                             socket(my $s, AF_UNIX, SOCK_STREAM, 0) or die "socket: $!";
                             bind($s, sockaddr_un("deletion.log")) or die "bind: $!";' "$state" ;;
        chain)      ln -s "$state/hop1" "$log"
                    ln -s "$state/hop2" "$state/hop1"
                    ln -s "$target"     "$state/hop2" ;;
        chain_live) echo "attacker rc" > "$target"
                    ln -s "$state/hop1" "$log"
                    ln -s "$target"     "$state/hop1" ;;
        hardlink)   echo "attacker rc" > "$target"
                    ln "$target" "$log" ;;
        *) hs_die "unknown variant '$variant'" ;;
    esac
}

size_of() { [ -f "$1" ] && wc -c < "$1" | tr -d '[:space:]' || printf '%s' '-'; }
exists()  { [ -e "$1" ] && printf 'yes' || printf 'no'; }

run_variant() {
    local variant="$1" P log target before_e before_s after_e after_s st el t0 t1 verdict

    P="$HS_WORK/v-$variant"
    mkdir -p "$P/home" "$P/trash" "$P/state" "$P/cwd"
    log="$P/state/deletion.log"
    target="$P/planted-target.rc"

    plant "$variant" "$log" "$target" "$P/state"

    printf '== variant=%s\n' "$variant"
    printf '   planted      : %s\n' "$(ls -ld "$log" 2>/dev/null | awk '{print $1, $2}')"
    before_e=$(exists "$target"); before_s=$(size_of "$target")
    printf '   target BEFORE: exists=%s size=%s\n' "$before_e" "$before_s"

    echo "victim" > "$P/cwd/victim.txt"
    HS_HOME="$P/home"; HS_TRASH="$P/trash"; HS_STATE="$P/state"
    t0=$(hs_now)
    hs_isolated "$P/cwd" "$HS_TIMEOUT_BIN" -s KILL 12 "$BRM" victim.txt > "$P/out.txt" 2>&1
    st=$?
    t1=$(hs_now)
    el=$(hs_elapsed "$t0" "$t1")
    after_e=$(exists "$target"); after_s=$(size_of "$target")

    printf '   exit=%s elapsed=%ss\n' "$st" "$el"
    printf '   target AFTER : exists=%s size=%s\n' "$after_e" "$after_s"
    printf '   log path now : %s\n' "$(ls -ld "$log" 2>/dev/null | awk '{print $1, $2}')"
    # 七種形狀沒有一種是合法日誌，所以「沒有出現拒絕訊息」本身就是缺陷。
    # 這一條不是裝飾：`[ -f ]` 被改成只擋 FIFO 的半套修法，唯一看得見的差別就是
    # socket 那一列從 yes 變成 no（實測 2026-08-20），target 檢查完全看不到它。
    # None of the seven planted shapes is a legal log, so a MISSING refusal is itself
    # a defect. Measured: the "reject only FIFOs" trimmed fix is invisible to the
    # target checks and shows up ONLY as socket flipping this line from yes to no.
    refused=no
    grep -q '已停止記錄' "$P/out.txt" 2>/dev/null && refused=yes
    printf '   refusal warning shown: %s\n' "$refused"
    printf '   victim still in cwd  : %s\n' "$(exists "$P/cwd/victim.txt")"

    verdict=SAFE
    if [ "$st" -eq 137 ] || [ "$st" -eq 124 ]; then
        verdict='DEFECT - HANG (timed out)'
    elif [ "$before_e" = no ] && [ "$after_e" = yes ]; then
        verdict='DEFECT - TARGET CREATED'
    elif [ "$before_s" != '-' ] && [ "$after_s" != '-' ] && [ "$before_s" != "$after_s" ]; then
        verdict="DEFECT - TARGET WRITTEN ($before_s -> $after_s)"
    elif [ "$refused" = no ]; then
        verdict='DEFECT - NO REFUSAL (the planted shape was accepted as a log)'
    fi

    # dangling 專屬（來自 implementation-evidence/probe-dangling.sh）：
    # 第二次刪除也要驗，否則只看得到「第一筆沒落到 target」。
    if [ "$variant" = dangling ]; then
        echo "victim2" > "$P/cwd/victim2.txt"
        hs_isolated "$P/cwd" "$HS_TIMEOUT_BIN" -s KILL 12 "$BRM" victim2.txt >/dev/null 2>&1
        printf '   after a SECOND deletion: target exists=%s size=%s\n' \
            "$(exists "$target")" "$(size_of "$target")"
        if [ "$(exists "$target")" = yes ]; then
            verdict='DEFECT - TARGET CREATED ON THE SECOND DELETION'
        fi
    fi

    # fifo 專屬（來自 implementation-evidence/probe-fifo.sh）：
    # 有沒有留下仍卡在 open() 的孤兒行程。
    if [ "$variant" = fifo ]; then
        sleep 1
        printf '   strays still blocked on the fifo: '
        if ps -eo pid,stat,command | grep -F "$P" | grep -v grep | grep -v 'probe-log-path'; then
            verdict="$verdict + STRAY PROCESSES"
        else
            printf 'none\n'
        fi
    fi

    printf '   --- better-rm output ---\n'
    hs_strip_ansi < "$P/out.txt" | sed 's/^/   | /'
    printf '   VERDICT: %s\n\n' "$verdict"
    case "$verdict" in
        SAFE) : ;;
        *) DEFECTS=$((DEFECTS + 1)) ;;
    esac
}

for v in $VARIANTS; do
    run_variant "$v"
done

if [ "$DEFECTS" -eq 0 ]; then
    printf 'RESULT: every planted shape was refused safely (VERDICT: SAFE throughout).\n'
    exit 0
fi
printf 'RESULT: %s variant(s) reported a DEFECT — that is a regression against ca02eca.\n' "$DEFECTS"
exit 1
