#!/bin/bash
#
# Better-RM 完整測試腳本
# Comprehensive Test Script for Better-RM
#
# 此腳本可在容器環境下測試 better-rm 的所有功能
# This script tests all features of better-rm in a container environment
#

# 顏色定義 (Color definitions)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 測試計數器 (Test counters)
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Better-RM 腳本路徑 (Better-RM script path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BETTER_RM="$SCRIPT_DIR/better-rm"

# 每一次執行都有自己的一組 fixture。這四個路徑本來是寫死的 /tmp/better-rm-test-*，而
# setup() 一開頭就對它們 rm -rf，於是兩個同時跑的 test-better-rm.sh 會互相把對方正在用的
# 目錄刪掉。實際發生過：2026-08-13 一位獨立驗收者量到「baseline 3 個失敗 vs HEAD 67 個
# 失敗」，差一步就要回報一次大規模退化，而真正的原因是另一個 session 在跑同一套測試。
# 這種假失敗特別危險，因為它看起來完全像真的退化——數字很大、只出現在 HEAD、重跑還會變。
# 加上 PID 之後，同一台機器上的並行執行各自獨立；BETTER_RM_TEST_RUN_ID 讓呼叫者（CI
# matrix、手動並跑）能指定自己的識別碼。
# Each run gets its own fixtures. These four paths were fixed literals under /tmp
# and setup() begins by rm -rf'ing them, so two concurrent test-better-rm.sh runs
# delete each other's live directories. This happened: on 2026-08-13 an independent
# reviewer measured "3 failures at baseline vs 67 at HEAD" and was one step from
# reporting a catastrophic regression that was entirely another session running the
# same suite. That failure mode is especially dangerous because it looks exactly
# like a real regression -- large, one-sided, and it changes on re-run.
TEST_RUN_ID="${BETTER_RM_TEST_RUN_ID:-$$}"

# 測試用的垃圾桶目錄 (Test trash directory)
TEST_TRASH_DIR="/tmp/better-rm-test-trash.$TEST_RUN_ID"

# 測試用的狀態目錄 (Test state directory)
TEST_STATE_DIR="/tmp/better-rm-test-state.$TEST_RUN_ID"

# 測試用的工作目錄 (Test working directory)
TEST_WORK_DIR="/tmp/better-rm-test-work.$TEST_RUN_ID"

# 測試不可寫狀態目錄時使用的一般檔案
# Regular file used to test an unavailable state directory
TEST_STATE_BLOCKER="/tmp/better-rm-test-state-blocker.$TEST_RUN_ID"

# 顯示測試標題 (Display test title)
test_title() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# 顯示測試項目 (Display test item)
test_item() {
    echo -e "${YELLOW}[測試 $TOTAL_TESTS] $1${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 測試成功 (Test passed)
test_pass() {
    echo -e "${GREEN}✓ 通過: $1${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

# 測試失敗 (Test failed)
test_fail() {
    echo -e "${RED}✗ 失敗: $1${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

# 清理測試環境 (Clean up test environment)
cleanup() {
    rm -rf "$TEST_TRASH_DIR" "$TEST_STATE_DIR" "$TEST_WORK_DIR" "$TEST_STATE_BLOCKER"
}

# 設置測試環境 (Setup test environment)
setup() {
    cleanup
    mkdir -p "$TEST_WORK_DIR"
    export TRASH_DIR="$TEST_TRASH_DIR"
    export BETTER_RM_STATE_DIR="$TEST_STATE_DIR"
}

# 驗證檔案是否在垃圾桶中 (Verify file is in trash)
verify_in_trash() {
    local pattern="$1"
    if find "$TEST_TRASH_DIR" -name "*${pattern}*" 2>/dev/null | grep -q .; then
        return 0
    else
        return 1
    fi
}

# 驗證日誌記錄 (Verify log entry)
verify_log_entry() {
    local log_file="$TEST_STATE_DIR/deletion.log"
    local pattern="$1"
    if [ -f "$log_file" ] && grep -q "$pattern" "$log_file"; then
        return 0
    else
        return 1
    fi
}

# 有界執行：跑一個命令，逾時就連同它整個 process group 殺掉。完成回傳 0（命令自己
# 的離開碼放在 RUN_BOUNDED_STATUS），逾時回傳 1。
# 為什麼需要：log_deletion 對非一般檔（FIFO）做重導向會停在 open() 上永遠不回來，
# 而「用真的卡住去證明卡住」的測試沒辦法放進任何 gate——它會把整套測試一起吊死。
# 為什麼不用 timeout(1)：macOS 沒有它，而 better-rm 必須在 stock /bin/bash 3.2.57
# 上跑；寫成「有 timeout 才設上限」等於在 macOS 上悄悄沒有上限。
# 為什麼殺整組：卡住的是 better-rm 底下那顆做重導向的 subshell，只殺 better-rm 會
# 留下一個永遠 open() 不回來的孤兒；set -m 讓背景工作自成一個 process group。
# Bounded run: execute a command and, on timeout, kill its whole process group.
# Returns 0 when it finished (the command's own exit code lands in
# RUN_BOUNDED_STATUS) and 1 when it timed out.
# Why it exists: log_deletion redirecting into a non-regular file (a FIFO) parks in
# open() forever, and a test that hangs to prove a hang cannot sit in any gate -- it
# takes the whole suite down with it.
# Why not timeout(1): macOS does not ship it and better-rm must run under stock
# /bin/bash 3.2.57, so "bound it only when timeout exists" is silently unbounded there.
# Why the whole group: what blocks is the redirect subshell under better-rm, so
# killing better-rm alone leaves an orphan stuck in open(); `set -m` puts the
# background job in its own process group so one kill reaches both.
RUN_BOUNDED_STATUS=""
run_bounded() {
    local limit="$1"
    shift
    local done_file="$TEST_WORK_DIR/.run-bounded-done"
    rm -f "$done_file" "$done_file.tmp"
    RUN_BOUNDED_STATUS=""
    set -m
    (
        "$@"
        printf '%s' "$?" > "$done_file.tmp"
        mv -f "$done_file.tmp" "$done_file"
    ) &
    local bounded_pid=$!
    set +m
    local waited=0
    while [ "$waited" -lt "$limit" ]; do
        if [ -f "$done_file" ]; then
            wait "$bounded_pid" 2>/dev/null
            RUN_BOUNDED_STATUS=$(cat "$done_file")
            rm -f "$done_file"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    kill -9 "-$bounded_pid" 2>/dev/null || kill -9 "$bounded_pid" 2>/dev/null
    wait "$bounded_pid" 2>/dev/null
    rm -f "$done_file" "$done_file.tmp"
    return 1
}

# ============================================================================
# 測試開始 (Tests Begin)
# ============================================================================

echo -e "${GREEN}Better-RM 完整測試套件${NC}"
echo -e "${GREEN}Better-RM Comprehensive Test Suite${NC}"
echo ""
echo "測試腳本: $BETTER_RM"
echo "垃圾桶目錄: $TEST_TRASH_DIR"
echo "狀態目錄: $TEST_STATE_DIR"
echo "工作目錄: $TEST_WORK_DIR"
echo ""

# ============================================================================
# 測試 1: 版本與說明 (Test 1: Version and Help)
# ============================================================================
test_title "測試 0: 測試框架本身"

test_item "setup() 不得刪掉另一個並行執行的 fixture"
# 造一個「另一個執行」會擁有的目錄，用的正是修掉之前那個寫死的名稱，所以這一列在寫死
# 的版本上必定紅：那個版本的 setup() 會把它刪掉。
# Plant a directory a CONCURRENT run would own, spelled with the fixed name these
# paths used to have, so this row is red on that version by construction: its
# setup() deletes exactly this path.
concurrent_fixture="/tmp/better-rm-test-work"
mkdir -p "$concurrent_fixture"
: > "$concurrent_fixture/canary"
setup
if [ -f "$concurrent_fixture/canary" ]; then
    test_pass "並行執行的 fixture 未被這一次的 setup 刪除"
else
    test_fail "setup() 刪掉了另一個執行的 fixture（fixture 路徑又變回寫死的了）"
fi
rm -rf "$concurrent_fixture"

test_item "四個 fixture 路徑都必須帶著這一次執行的識別碼"
# 上一項是行為，這一項是結構：任何一個路徑被改回寫死的字面值，這裡就紅。兩項都要，
# 因為行為那一項只驗到 work 目錄，而 trash/state/blocker 同樣會互相踩。
# The row above is behavioural and only exercises the work directory; this one is
# structural and covers all four, so trash/state/blocker cannot quietly go back to
# a fixed literal while the behavioural row stays green.
runid_missing=""
for fixture_path in "$TEST_TRASH_DIR" "$TEST_STATE_DIR" "$TEST_WORK_DIR" "$TEST_STATE_BLOCKER"; do
    case "$fixture_path" in
      *".$TEST_RUN_ID") ;;
      *) runid_missing="$runid_missing $fixture_path" ;;
    esac
done
if [ -z "$runid_missing" ]; then
    test_pass "四個 fixture 路徑都以執行識別碼結尾"
else
    test_fail "這些 fixture 路徑沒有帶執行識別碼:${runid_missing}"
fi

test_title "測試 1: 版本與說明資訊"

test_item "測試 --version 參數"
if "$BETTER_RM" --version | grep -q "better-rm 1.5.0"; then
    test_pass "--version 顯示正確版本"
else
    test_fail "--version 版本不正確"
fi

test_item "測試 --help 參數"
if "$BETTER_RM" --help | grep -q "用法"; then
    test_pass "--help 顯示說明訊息"
else
    test_fail "--help 未顯示說明訊息"
fi

test_item "-- 的說明不得從 --help、README 與 CHANGELOG 消失"
# 文件漂移護欄。-- 是使用者唯一能指名破折號開頭檔案的寫法，說明從任何一份使用者會
# 看的文件掉了，這個功能對他就等於不存在，而測試套件不會有任何一項變紅。
# 三份都只釘「那一條的主詞」——--help 的選項欄位、README 選項表格的那一列、
# CHANGELOG 那一條的開頭：描述文字怎麼改寫都不會紅，整條被刪掉才會紅。
# 刻意不掃整份 README（-- 在 README 出現三處，只掃全檔的話刪掉選項表格那一列仍然
# 會綠，護欄就只剩一半）。
# CHANGELOG 是後來補進來的，理由值得寫下來：曾經發生過「三份文件裡只有 CHANGELOG
# 說錯，而這條護欄全綠」——它當時根本沒被涵蓋。
# 也刻意「不」去比對描述句本身。那次出錯的形狀是「句子在，但內容是錯的」，而 grep
# 只驗得了「句子在不在」，驗不了「說得對不對」；補一條句子比對只會製造覆蓋的假象，
# 正是這輪一直在清的空洞守衛。真正釘住行為的是 f514c2c 那條拒絕測試。
# Documentation-drift guard. -- is the only way a user can name a file whose name
# starts with a dash, so an entry quietly dropped from any document a user reads
# makes the feature nonexistent for them without turning anything in this suite red.
# All three pin only the subject of the entry -- the option field in --help, the
# option-table row in the README, the start of the CHANGELOG entry: rewording the
# description stays green, deleting the entry goes red. The README is deliberately
# not searched as a whole (-- is mentioned in three places there, so a whole-file
# grep would stay green after the table row was deleted, which is half a guard).
# CHANGELOG was added later and the reason is worth recording: the changelog was
# once the one document of the three that was wrong while this guard was green --
# it simply was not covered.
# Comparing the description sentence itself is deliberately NOT done. The shape of
# that failure was "the sentence is present and false", and a grep can only test
# presence, never truth; adding a sentence match would manufacture the appearance
# of coverage, which is the hollow guard this whole round has been removing. What
# actually pins the behaviour is the refusal test from f514c2c.
terminator_doc_gaps=""
if ! "$BETTER_RM" --help | grep -q '^  -- '; then
    terminator_doc_gaps="$terminator_doc_gaps --help"
fi
if ! grep -q "^| \`--\` |" "$SCRIPT_DIR/README.md"; then
    terminator_doc_gaps="$terminator_doc_gaps README.md"
fi
if ! grep -q "^- \`--\` " "$SCRIPT_DIR/CHANGELOG.md"; then
    terminator_doc_gaps="$terminator_doc_gaps CHANGELOG.md"
fi
if [ -z "$terminator_doc_gaps" ]; then
    test_pass "--help、README 與 CHANGELOG 都還列著 -- 選項"
else
    test_fail "以下文件不再列出 -- 選項：$terminator_doc_gaps"
fi

# ============================================================================
# 測試 2: 基本檔案刪除 (Test 2: Basic File Deletion)
# ============================================================================
test_title "測試 2: 基本檔案刪除功能"

setup
cd "$TEST_WORK_DIR"

test_item "刪除單一檔案"
echo "test content" > file1.txt
if "$BETTER_RM" file1.txt && [ ! -e file1.txt ] && verify_in_trash "file1.txt"; then
    test_pass "單一檔案成功移至垃圾桶"
else
    test_fail "單一檔案刪除失敗"
fi

test_item "刪除多個檔案"
echo "file2" > file2.txt
echo "file3" > file3.txt
if "$BETTER_RM" file2.txt file3.txt && [ ! -e file2.txt ] && [ ! -e file3.txt ] && \
   verify_in_trash "file2.txt" && verify_in_trash "file3.txt"; then
    test_pass "多個檔案成功移至垃圾桶"
else
    test_fail "多個檔案刪除失敗"
fi

# ============================================================================
# 測試 3: 目錄刪除 (Test 3: Directory Deletion)
# ============================================================================
test_title "測試 3: 目錄刪除功能"

setup
cd "$TEST_WORK_DIR"

test_item "遞迴刪除目錄 (-r)"
mkdir -p testdir/subdir
echo "content" > testdir/file.txt
echo "subcontent" > testdir/subdir/subfile.txt
if "$BETTER_RM" -r testdir && [ ! -e testdir ] && verify_in_trash "testdir"; then
    test_pass "目錄成功遞迴刪除"
else
    test_fail "目錄刪除失敗"
fi

test_item "刪除空目錄"
mkdir emptydir
if "$BETTER_RM" -r emptydir && [ ! -e emptydir ] && verify_in_trash "emptydir"; then
    test_pass "空目錄成功刪除"
else
    test_fail "空目錄刪除失敗"
fi

test_item "不加 -r 刪除目錄應失敗"
mkdir testdir2
if "$BETTER_RM" testdir2 2>/dev/null; then
    test_fail "不加 -r 卻成功刪除目錄（不應該）"
else
    test_pass "不加 -r 正確拒絕刪除目錄"
fi
rm -rf testdir2

# ============================================================================
# 測試 4: 特殊字元檔名 (Test 4: Special Characters in Filenames)
# ============================================================================
test_title "測試 4: 特殊字元檔名處理"

setup
cd "$TEST_WORK_DIR"

test_item "檔名含空格"
echo "content" > "file with spaces.txt"
if "$BETTER_RM" "file with spaces.txt" && [ ! -e "file with spaces.txt" ]; then
    test_pass "空格檔名成功處理"
else
    test_fail "空格檔名處理失敗"
fi

test_item "檔名含特殊字元"
echo "content" > "file-with_special.chars.txt"
if "$BETTER_RM" "file-with_special.chars.txt" && [ ! -e "file-with_special.chars.txt" ]; then
    test_pass "特殊字元檔名成功處理"
else
    test_fail "特殊字元檔名處理失敗"
fi

test_item "中文檔名"
echo "內容" > "測試檔案.txt"
if "$BETTER_RM" "測試檔案.txt" && [ ! -e "測試檔案.txt" ]; then
    test_pass "中文檔名成功處理"
else
    test_fail "中文檔名處理失敗"
fi

# ============================================================================
# 測試 5: 符號連結 (Test 5: Symbolic Links)
# ============================================================================
test_title "測試 5: 符號連結處理"

setup
cd "$TEST_WORK_DIR"

test_item "刪除符號連結"
echo "target" > target.txt
ln -s target.txt symlink.txt
if "$BETTER_RM" symlink.txt && [ ! -L symlink.txt ] && [ -e target.txt ]; then
    test_pass "符號連結成功刪除（目標檔案保留）"
else
    test_fail "符號連結刪除失敗"
fi

test_item "以原始 link 名還原符號連結"
setup
cd "$TEST_WORK_DIR"
echo "restore target content" > restore-target.txt
ln -s restore-target.txt restore-link.txt
target_identity_before=$(stat -c '%d:%i' restore-target.txt 2>/dev/null ||
    stat -f '%d:%i' restore-target.txt 2>/dev/null)
"$BETTER_RM" restore-link.txt
if "$BETTER_RM" --restore restore-link.txt >/dev/null 2>&1 &&
   [ -L restore-link.txt ] &&
   [ "$(readlink restore-link.txt)" = "restore-target.txt" ] &&
   [ "$(cat restore-target.txt)" = "restore target content" ]; then
    target_identity_after=$(stat -c '%d:%i' restore-target.txt 2>/dev/null ||
        stat -f '%d:%i' restore-target.txt 2>/dev/null)
    if [ "$target_identity_after" = "$target_identity_before" ]; then
        test_pass "符號連結以原名還原且 target 身分不變"
    else
        test_fail "還原符號連結時 target 身分遭到改變"
    fi
else
    test_fail "無法以原始 link 名還原符號連結"
fi

# ============================================================================
# 測試 6: 時間戳記與 Hash (Test 6: Timestamp and Hash)
# ============================================================================
test_title "測試 6: 時間戳記與內容 Hash"

setup
cd "$TEST_WORK_DIR"

test_item "檔名包含時間戳記和 Hash"
echo "content for hash" > hashtest.txt
"$BETTER_RM" hashtest.txt
if find "$TEST_TRASH_DIR" -name "hashtest.txt__*__*" | grep -q .; then
    test_pass "檔名包含時間戳記和 Hash"
else
    test_fail "檔名格式不正確"
fi

test_item "相同檔名但不同內容產生不同 Hash"
echo "content1" > test.txt
"$BETTER_RM" test.txt
sleep 0.01  # 確保時間戳記不同
hash1=$(find "$TEST_TRASH_DIR" -name "test.txt__*" | sort | head -1 | awk -F'__' '{print $NF}')

echo "content2" > test.txt
"$BETTER_RM" test.txt
hash2=$(find "$TEST_TRASH_DIR" -name "test.txt__*" | sort | tail -1 | awk -F'__' '{print $NF}')

if [ -n "$hash1" ] && [ -n "$hash2" ] && [ "$hash1" != "$hash2" ]; then
    test_pass "不同內容產生不同 Hash (hash1=$hash1, hash2=$hash2)"
else
    test_fail "不同內容產生相同 Hash 或未找到 Hash (hash1=$hash1, hash2=$hash2)"
fi

test_item "空檔案的 Hash"
touch empty.txt
"$BETTER_RM" empty.txt
if find "$TEST_TRASH_DIR" -name "empty.txt__*__d41d8cd98f00b204e9800998ecf8427e" | grep -q .; then
    test_pass "空檔案 Hash 正確 (MD5 of empty string)"
else
    test_fail "空檔案 Hash 不正確"
fi

# ============================================================================
# 測試 7: 刪除日誌 (Test 7: Deletion Log)
# ============================================================================
test_title "測試 7: 刪除日誌功能"

setup
cd "$TEST_WORK_DIR"

test_item "日誌檔案自動創建"
echo "test" > logtest.txt
"$BETTER_RM" logtest.txt
if [ -f "$TEST_STATE_DIR/deletion.log" ] && [ ! -e "$TEST_TRASH_DIR/.deletion_log" ]; then
    test_pass "日誌檔案成功創建"
else
    test_fail "日誌檔案未創建"
fi

test_item "狀態目錄與日誌使用限制性權限"
state_mode=$(stat -c '%a' "$TEST_STATE_DIR" 2>/dev/null || stat -f '%Lp' "$TEST_STATE_DIR" 2>/dev/null)
log_mode=$(stat -c '%a' "$TEST_STATE_DIR/deletion.log" 2>/dev/null || stat -f '%Lp' "$TEST_STATE_DIR/deletion.log" 2>/dev/null)
if [ "$state_mode" = "700" ] && [ "$log_mode" = "600" ]; then
    test_pass "狀態目錄與日誌權限正確"
else
    test_fail "狀態目錄或日誌權限不正確 (directory=$state_mode, log=$log_mode)"
fi

test_item "日誌記錄檔案刪除"
if verify_log_entry "logtest.txt" && verify_log_entry "file"; then
    test_pass "日誌正確記錄檔案刪除"
else
    test_fail "日誌未記錄檔案刪除"
fi

test_item "日誌記錄目錄刪除"
mkdir logdir
echo "content" > logdir/file.txt
"$BETTER_RM" -r logdir
if verify_log_entry "logdir" && verify_log_entry "directory"; then
    test_pass "日誌正確記錄目錄刪除"
else
    test_fail "日誌未記錄目錄刪除"
fi

test_item "日誌記錄符號連結"
echo "target" > logtarget.txt
ln -s logtarget.txt logsymlink.txt
"$BETTER_RM" logsymlink.txt
if verify_log_entry "symlink"; then
    test_pass "日誌正確記錄符號連結"
else
    test_fail "日誌未記錄符號連結"
fi

test_item "日誌格式正確"
log_file="$TEST_STATE_DIR/deletion.log"
# v2 紀錄的路徑欄位一定不含未轉義的 |，否則還原時的切割就會錯位
# A v2 record never carries an unescaped '|' in a path field; otherwise the
# split during restore lands on the wrong boundary.
if grep -E "^[0-9]{8}_[0-9]{6}_[0-9]+ \| v2 \| [^|]+ \| [^|]+ \| [^|]+ \| (file|directory|symlink)$" "$log_file" >/dev/null 2>&1; then
    test_pass "日誌格式正確"
else
    test_fail "日誌格式不正確"
fi

test_item "無法建立日誌目錄時刪除仍成功且不洩漏 Shell 錯誤"
printf 'blocker\n' > "$TEST_STATE_BLOCKER"
echo "unavailable state test" > unavailable-state.txt
log_failure_output=$(BETTER_RM_STATE_DIR="$TEST_STATE_BLOCKER/child" "$BETTER_RM" unavailable-state.txt 2>&1)
log_failure_status=$?
if [ $log_failure_status -eq 0 ] && [ ! -e unavailable-state.txt ] && \
   verify_in_trash "unavailable-state.txt" && \
   echo "$log_failure_output" | grep -q "無法建立日誌目錄" && \
   ! echo "$log_failure_output" | grep -Eq "Permission denied|Operation not permitted|Not a directory"; then
    test_pass "日誌失敗不影響刪除且輸出受控"
else
    test_fail "日誌失敗時的刪除結果或錯誤輸出不正確"
fi

test_item "日誌路徑是既有 symlink 時停止記錄且不寫進 target"
# `[ -f ]` 與 `>>` 都跟隨 symlink，所以預先放好的連結會把每一筆刪除紀錄 append 到
# 別人的檔案裡。這裡釘的是「target 一個位元組都沒變」，不是「有沒有警告」。
# Both `[ -f ]` and `>>` follow a symlink, so a pre-planted link appends every
# deletion record into somebody else's file. What is pinned here is that the
# target does not grow by a single byte, not merely that a warning appeared.
symlink_log_state="$TEST_WORK_DIR/symlink-log-state"
symlink_log_victim="$TEST_WORK_DIR/symlink-log-victim.json"
mkdir -p "$symlink_log_state"
printf '{"keep":"me"}\n' > "$symlink_log_victim"
ln -s "$symlink_log_victim" "$symlink_log_state/deletion.log"
symlink_log_before=$(wc -c < "$symlink_log_victim" | tr -d ' ')
echo "symlink log test" > symlink-log.txt
symlink_log_output=$(BETTER_RM_STATE_DIR="$symlink_log_state" "$BETTER_RM" symlink-log.txt 2>&1)
symlink_log_status=$?
symlink_log_after=$(wc -c < "$symlink_log_victim" | tr -d ' ')
if [ $symlink_log_status -eq 0 ] && [ ! -e symlink-log.txt ] && \
   verify_in_trash "symlink-log.txt" && \
   [ "$symlink_log_after" = "$symlink_log_before" ] && \
   [ -L "$symlink_log_state/deletion.log" ] && \
   echo "$symlink_log_output" | grep -q "已停止記錄"; then
    test_pass "symlink 日誌被拒絕，刪除仍成功且 target 未被污染"
else
    test_fail "symlink 日誌未被拒絕 (status=$symlink_log_status, target ${symlink_log_before}→${symlink_log_after} bytes)"
fi

test_item "日誌路徑另有 hard link 時停止記錄且不寫進該 inode"
# hard link 騙得過「非 symlink + 一般檔 + 本人所有」三項檢查（-L 否、-f 是、-O 是），
# 只有 link 數看得見第二個名字。這一項先斷言那三項確實成立，再斷言紀錄沒有落地：
# 少了 link 數那一條，這個測試就會紅。
# A hard link passes "not a symlink + regular + owned" (-L no, -f yes, -O yes);
# only the link count sees the second name. This asserts those three hold first
# and that no record landed second, so dropping the link-count clause turns it red.
hardlink_log_state="$TEST_WORK_DIR/hardlink-log-state"
hardlink_log_victim="$TEST_WORK_DIR/hardlink-log-victim.json"
mkdir -p "$hardlink_log_state"
printf '{"k":1}\n' > "$hardlink_log_victim"
ln "$hardlink_log_victim" "$hardlink_log_state/deletion.log"
hardlink_log_before=$(wc -c < "$hardlink_log_victim" | tr -d ' ')
echo "hardlink log test" > hardlink-log.txt
hardlink_log_output=$(BETTER_RM_STATE_DIR="$hardlink_log_state" "$BETTER_RM" hardlink-log.txt 2>&1)
hardlink_log_status=$?
hardlink_log_after=$(wc -c < "$hardlink_log_victim" | tr -d ' ')
if [ $hardlink_log_status -eq 0 ] && [ ! -e hardlink-log.txt ] && \
   verify_in_trash "hardlink-log.txt" && \
   [ ! -L "$hardlink_log_state/deletion.log" ] && \
   [ -f "$hardlink_log_state/deletion.log" ] && \
   [ -O "$hardlink_log_state/deletion.log" ] && \
   [ "$hardlink_log_after" = "$hardlink_log_before" ] && \
   echo "$hardlink_log_output" | grep -q "已停止記錄"; then
    test_pass "hard link 日誌被拒絕，刪除仍成功且該 inode 未被寫入"
else
    test_fail "hard link 日誌未被拒絕 (status=$hardlink_log_status, inode ${hardlink_log_before}→${hardlink_log_after} bytes)"
fi

test_item "日誌路徑是 FIFO 時停止記錄，而且不會卡住"
# 少了「一般檔」那一條，FIFO 走得過其餘三項（-L 否、-O 是、link 數 1），接著
# log_deletion 的 `> "$log_file"` 就停在 open() 上，等一個永遠不會出現的讀端——
# 這不是少記一筆，是整個 rm 掛在那裡不回來。這道守衛跑在這台機器上的每一次刪除，
# 所以少掉那一條的代價是「rm 不會結束」，比漏記嚴重得多。
# 這裡釘的是「有在時限內結束」，用 run_bounded 而不是直接呼叫：測試不能用真的
# 卡住去證明卡住。
# Without the regular-file clause a FIFO passes the other three (-L no, -O yes, one
# link) and log_deletion's `> "$log_file"` then parks in open() waiting for a reader
# that never arrives -- not a missing record, an rm that never returns. This guard
# runs on every deletion on this machine, so dropping that clause costs far more than
# a lost log line. What is pinned here is that the run FINISHES, and it goes through
# run_bounded because a test must not hang in order to prove a hang.
fifo_log_state="$TEST_WORK_DIR/fifo-log-state"
fifo_log_output="$TEST_WORK_DIR/fifo-log-output.txt"
mkdir -p "$fifo_log_state"
mkfifo "$fifo_log_state/deletion.log"
echo "fifo log test" > fifo-log.txt
fifo_log_timed_out=0
run_bounded 15 env BETTER_RM_STATE_DIR="$fifo_log_state" "$BETTER_RM" fifo-log.txt \
    > "$fifo_log_output" 2>&1 || fifo_log_timed_out=1
if [ "$fifo_log_timed_out" -eq 0 ] && [ "$RUN_BOUNDED_STATUS" = "0" ] && \
   [ ! -e fifo-log.txt ] && verify_in_trash "fifo-log.txt" && \
   [ -p "$fifo_log_state/deletion.log" ] && \
   grep -q "已停止記錄" "$fifo_log_output"; then
    test_pass "FIFO 日誌被拒絕，刪除在時限內完成且 FIFO 未被寫入"
else
    test_fail "FIFO 日誌未被拒絕或執行卡住 (timed_out=$fifo_log_timed_out, status=${RUN_BOUNDED_STATUS:-timeout})"
fi

test_item "日誌路徑是斷掉的 symlink 時停止記錄且不把 target 建出來"
# 佔用判斷寫成 `[ -e ] || [ -L ]`，是因為斷掉的 symlink 只有後者看得見：拿掉 `[ -L ]`
# 那一邊，這種情況下整個綁定檢查根本不會被叫到，接著 `> "$log_file"` 會沿著連結把
# 目標檔建出來——把連結指向一個還不存在的 shell rc，第一次刪除就替對方建好那個檔，
# 而檔案內容是 better-rm 自己寫的日誌位元組。
# 這裡釘的是「target 沒有被建出來」，不是「有沒有警告」。
# The occupancy test is `[ -e ] || [ -L ]` because only the second operand sees a
# dangling symlink: drop `[ -L ]` and the binding check is never reached in this case,
# after which `> "$log_file"` follows the link and CREATES the target -- aim the link
# at a shell rc that does not exist yet and the first deletion creates it, filled with
# better-rm's own log bytes. What is pinned is that the target was NOT created, not
# that a warning appeared.
dangling_log_state="$TEST_WORK_DIR/dangling-log-state"
dangling_log_target="$TEST_WORK_DIR/dangling-log-target.rc"
mkdir -p "$dangling_log_state"
ln -s "$dangling_log_target" "$dangling_log_state/deletion.log"
echo "dangling log test" > dangling-log.txt
dangling_log_output=$(BETTER_RM_STATE_DIR="$dangling_log_state" "$BETTER_RM" dangling-log.txt 2>&1)
dangling_log_status=$?
if [ $dangling_log_status -eq 0 ] && [ ! -e dangling-log.txt ] && \
   verify_in_trash "dangling-log.txt" && \
   [ ! -e "$dangling_log_target" ] && \
   [ -L "$dangling_log_state/deletion.log" ] && \
   echo "$dangling_log_output" | grep -q "已停止記錄"; then
    test_pass "斷掉的 symlink 日誌被拒絕，刪除仍成功且 target 未被建立"
else
    test_fail "斷掉的 symlink 日誌未被拒絕 (status=$dangling_log_status, target 被建立=$([ -e "$dangling_log_target" ] && echo yes || echo no))"
fi

test_item "KNOWN-RESIDUALS.md 的三條與程式碼事實仍然對得上（雙向釘）"
# 為什麼需要：這三項是刻意不修的既有殘留，前四輪 review 每一輪都重新推導了一次。
# 光把理由寫進 md 擋不住第五次——文字會爛。所以這裡兩邊都釘：文字不見了會紅，
# 而且**底下的程式碼事實變了也會紅**。第二半才是重點，它把「修好了卻忘了刪那段
# 文字」變成一次失敗，而不是一段悄悄過期的謊。
# 釘的是「理由」不是「結論」：結論會被一句「以上作廢」原地否定（2026-08-18 的
# 對抗驗收實測三種改寫全部得手），理由不會——沒有人會為了繞過測試去補一段假的
# O_NOFOLLOW 論證。這個極限在 KNOWN-RESIDUALS.md 裡也明說了。
# Why it exists: three deliberately-unfixed residuals that four review rounds each
# re-derived from scratch. Prose alone will not stop the fifth. This pins BOTH
# directions: red if the text goes, red if the code fact it describes changes -- so
# "fixed it but forgot the note" fails loudly instead of rotting quietly. It pins the
# REASONS, not the verdicts: a verdict can be negated in place, a reason cannot.
residuals_doc="$SCRIPT_DIR/KNOWN-RESIDUALS.md"
residuals_problems=""
if [ ! -f "$residuals_doc" ]; then
    residuals_problems="KNOWN-RESIDUALS.md 不存在"
else
    # R1 — 文字面要留住「正確修法是驗 fd 而不是路徑」這個理由。
    grep -q 'O_NOFOLLOW' "$residuals_doc" ||
        residuals_problems="$residuals_problems R1的修法方向(O_NOFOLLOW)從文件消失;"
    # R1 — 程式碼面：綁定檢查仍然是對「路徑」做的。若哪天改成驗 fd，殘留就消失了，
    # 這段文字必須跟著刪。
    grep -q 'log_file_is_bound() {' "$BETTER_RM" ||
        residuals_problems="$residuals_problems R1所描述的log_file_is_bound已不存在;"
    # R2 — 文字面要留住「無 root 不可測」這個理由，否則下一輪會有人硬寫一個假測試。
    grep -q '無法在無 root 的情況下測試' "$residuals_doc" ||
        residuals_problems="$residuals_problems R2的不可測理由從文件消失;"
    # R2 — 程式碼面：那個沒被覆蓋的 clause 還在。被刪掉的話這條殘留就不成立了。
    grep -q '\[ -O "\$path" \] || return 1' "$BETTER_RM" ||
        residuals_problems="$residuals_problems R2所指的[-O]clause已不在better-rm裡;"
    # R3 — 文字面要留住「兩邊都紅＝既有問題」，這點被三份報告各自誤判過。
    grep -q '兩邊都紅' "$residuals_doc" ||
        residuals_problems="$residuals_problems R3的對稱性結論從文件消失;"
    # R3 — 程式碼面：那個牆鐘預算還在。換成不看牆鐘的寫法就該刪這條。
    grep -q 'const budgetMs = 1000;' "$SCRIPT_DIR/test-hooks.js" ||
        residuals_problems="$residuals_problems R3所指的1000ms牆鐘預算已不在test-hooks.js裡;"
fi
if [ -z "$residuals_problems" ]; then
    test_pass "三條殘留的理由與其程式碼事實一致"
else
    test_fail "KNOWN-RESIDUALS.md 與程式碼不同步:$residuals_problems (修好了就把對應那條刪掉，別留著爛)"
fi

test_item "0644 的既有日誌照樣記錄與還原"
# 權限刻意不列入綁定條件：從備份還原、或落在 FAT／雲端掛載點的日誌常常是 0644，
# 若一併拒絕就會讓記錄與 --restore 一起靜默失效。
# Mode is deliberately not part of the binding: a log restored from a backup or
# living on a FAT/cloud mount is routinely 0644, and rejecting it would kill
# logging and --restore together and in silence.
loose_mode_state="$TEST_WORK_DIR/loose-mode-state"
mkdir -p "$loose_mode_state"
printf '%s\n' "LOOSE MODE FIRST" > loose-mode-seed.txt
BETTER_RM_STATE_DIR="$loose_mode_state" "$BETTER_RM" loose-mode-seed.txt >/dev/null 2>&1
chmod 644 "$loose_mode_state/deletion.log"
printf '%s\n' "LOOSE MODE LEDGER" > loose-mode.txt
BETTER_RM_STATE_DIR="$loose_mode_state" "$BETTER_RM" loose-mode.txt >/dev/null 2>&1
loose_mode_restore_status=0
BETTER_RM_STATE_DIR="$loose_mode_state" "$BETTER_RM" --restore loose-mode.txt >/dev/null 2>&1 ||
    loose_mode_restore_status=$?
if grep -q "loose-mode.txt" "$loose_mode_state/deletion.log" && \
   [ "$loose_mode_restore_status" -eq 0 ] && [ -f loose-mode.txt ] && \
   [ "$(cat loose-mode.txt)" = "LOOSE MODE LEDGER" ]; then
    test_pass "0644 日誌仍可記錄與還原"
else
    test_fail "0644 日誌記錄或還原失敗 (restore status=$loose_mode_restore_status)"
fi

test_item "日誌欄位轉義 shell 元字元，紀錄被 source 也不會執行命令"
# 一整筆紀錄長得就像一條 shell pipeline，欄位就是其中的命令。日誌被導到 shell rc 上
# 時，檔名裡未轉義的 ; & ` $( ) 就是真的會執行——四種寫法在修正前全部實測執行成功。
# A whole record reads like a shell pipeline whose fields are its commands. With
# the log aimed at a shell rc, an unescaped ';', '&', '`' or '$( )' in a filename
# really does execute -- all four were measured executing before this change.
meta_exec_failures=""
meta_case_index=0
for meta_payload in 'semi; touch ACE-META; :' 'amp & touch ACE-META & :' 'grave`touch ACE-META`' 'dollar$(touch ACE-META)'; do
    meta_case_index=$((meta_case_index + 1))
    meta_dir="$TEST_WORK_DIR/meta-exec-$meta_case_index"
    mkdir -p "$meta_dir/state" "$meta_dir/work"
    printf '%s\n' "META" > "$meta_dir/work/$meta_payload"
    ( cd "$meta_dir/work" && BETTER_RM_STATE_DIR="$meta_dir/state" "$BETTER_RM" -- "$meta_payload" ) >/dev/null 2>&1
    grep -v '^#' "$meta_dir/state/deletion.log" 2>/dev/null | tail -1 > "$meta_dir/record"
    ( cd "$meta_dir" && bash -c '. ./record' ) >/dev/null 2>&1
    if [ -e "$meta_dir/ACE-META" ]; then
        meta_exec_failures="$meta_exec_failures '$meta_payload'"
    fi
done
if [ -z "$meta_exec_failures" ]; then
    test_pass "shell 元字元在日誌欄位被轉義，source 紀錄不會執行命令"
else
    test_fail "日誌紀錄被 source 時執行了命令：$meta_exec_failures"
fi

test_item "含 shell 元字元的檔名仍可由日誌還原"
# 轉義只有在還原也讀得回來時才算數；元字元檔名要能原樣回到原處。
# The escaping only counts if restore reads it back: a metacharacter filename
# must return to its original path byte for byte.
meta_restore_state="$TEST_WORK_DIR/meta-restore-state"
meta_restore_name='restore;&`$(x) meta.txt'
mkdir -p "$meta_restore_state"
printf '%s\n' "META ROUND TRIP" > "$meta_restore_name"
BETTER_RM_STATE_DIR="$meta_restore_state" "$BETTER_RM" -- "$meta_restore_name" >/dev/null 2>&1
meta_restore_status=0
BETTER_RM_STATE_DIR="$meta_restore_state" "$BETTER_RM" --restore "$meta_restore_name" >/dev/null 2>&1 ||
    meta_restore_status=$?
if [ "$meta_restore_status" -eq 0 ] && [ -f "$meta_restore_name" ] && \
   [ "$(cat "$meta_restore_name")" = "META ROUND TRIP" ]; then
    test_pass "元字元檔名的日誌紀錄可正確還原"
else
    test_fail "元字元檔名還原失敗 (status=$meta_restore_status)"
fi

# ============================================================================
# 測試 8: 參數選項 (Test 8: Command Options)
# ============================================================================
test_title "測試 8: 命令參數選項"

setup
cd "$TEST_WORK_DIR"

test_item "詳細模式 (-v)"
echo "verbose test" > vtest.txt
if "$BETTER_RM" -v vtest.txt 2>&1 | grep -q "已移除"; then
    test_pass "-v 參數顯示詳細訊息"
else
    test_fail "-v 參數未顯示詳細訊息"
fi

test_item "強制模式 (-f) 忽略不存在的檔案"
if "$BETTER_RM" -f nonexistent.txt 2>/dev/null; then
    test_pass "-f 參數正確忽略不存在的檔案"
else
    test_fail "-f 參數未正確處理"
fi

test_item "組合參數 (-rf)"
mkdir -p rftest/subdir
echo "content" > rftest/file.txt
if "$BETTER_RM" -rf rftest && [ ! -e rftest ]; then
    test_pass "-rf 組合參數正常工作"
else
    test_fail "-rf 組合參數失敗"
fi

test_item "-- 之後的引數一律視為檔名"
# 少了 --) 分支時，裸 -- 會掉進 -*) 的組合參數解析，並在 *) 以
# 「無效的選項 -- '-'」結束，於是 `rm -- -foo.txt`（唯一可攜、能刪掉破折號開頭
# 檔名的寫法）在這裡什麼都刪不掉，真正的 rm 卻會刪。
# Without a `--)` case the bare -- fell into the combined-option branch and died
# at its default with "invalid option -- '-'", so `rm -- -foo.txt` -- the only
# portable way to delete a file whose name starts with a dash -- deleted nothing
# here while the real rm deletes it.
printf '%s\n' "DASH CONTENT" > ./-dash.txt
dash_status=0
"$BETTER_RM" -- -dash.txt >/dev/null 2>&1 || dash_status=$?
if [ "$dash_status" -eq 0 ] && [ ! -e ./-dash.txt ] && verify_in_trash "dash.txt"; then
    test_pass "-- 之後的 -dash.txt 被當成檔名刪除"
else
    test_fail "-- 之後的引數未被當成檔名 (status=$dash_status)"
fi

test_item "-- 之前的選項仍然生效"
mkdir -p ./-dashdir/sub
echo "content" > ./-dashdir/sub/file.txt
dashdir_status=0
"$BETTER_RM" -rf -- -dashdir >/dev/null 2>&1 || dashdir_status=$?
if [ "$dashdir_status" -eq 0 ] && [ ! -e ./-dashdir ]; then
    test_pass "-rf -- 破折號開頭目錄遞迴刪除成功"
else
    test_fail "-- 之前的 -rf 未生效 (status=$dashdir_status)"
fi

test_item "沒有 -- 時破折號開頭仍視為選項"
# 反套套邏輯：修好的是 -- 這個終止符，不是「把所有引數都當檔名」。
# Anti-tautology: what got fixed is the terminator, not "treat every argument as
# a pathname" -- an unguarded dash-leading argument must still be an option.
printf '%s\n' "STILL AN OPTION" > ./-zz.txt
zz_status=0
"$BETTER_RM" -zz.txt >/dev/null 2>&1 || zz_status=$?
if [ "$zz_status" -ne 0 ] && [ -f ./-zz.txt ]; then
    test_pass "沒有 -- 時 -zz.txt 仍被當成無效選項"
else
    test_fail "沒有 -- 時破折號開頭被誤當成檔名 (status=$zz_status)"
fi

test_item "--restore 同樣接受 -- 終止符"
# 刪除端認得 -- 而還原端不認得，等於讓 -- 想解決的那一類檔名變成單向：刪得掉、還原
# 不回來。實測 `--restore -- -dash.txt` 以「選項 '--restore' 需要一個引數」失敗，
# 唯一能還原的寫法是 `--restore ./-dash.txt`。
# Honouring -- on the delete side only makes exactly the class of names -- exists
# for one-way: deletable but not restorable. Measured: `--restore -- -dash.txt`
# failed with "option '--restore' requires an argument" and the only spelling that
# restored the file was `--restore ./-dash.txt`.
dash_restore_status=0
"$BETTER_RM" --restore -- -dash.txt >/dev/null 2>&1 || dash_restore_status=$?
if [ "$dash_restore_status" -eq 0 ] && [ -f ./-dash.txt ] && \
   [ "$(cat ./-dash.txt)" = "DASH CONTENT" ]; then
    test_pass "--restore -- -dash.txt 還原成功"
else
    test_fail "--restore 未接受 -- 終止符 (status=$dash_restore_status)"
fi

# 每個探測都是一個完整的引數陣列，不是一個要靠 word splitting 拆開的字串。
# 舊寫法用 $restore_bad_args 不加引號展開，得靠一行 SC2086 的抑制註解壓警告，而且
# 含空白的引數根本測不了——那正好是「破折號開頭」判斷最容易出錯的形狀。
# Each probe is a full argument array rather than a string relying on word
# splitting. The previous form expanded $restore_bad_args unquoted, needed a
# suppression comment for SC2086, and could not express an argument containing a
# space -- exactly the shape where a dash-leading test is easiest to get wrong.
check_restore_refusal() {
    local label="$1"
    shift
    local out status=0
    out=$("$BETTER_RM" "$@" 2>&1) || status=$?
    if [ "$status" -eq 0 ]; then
        restore_contract_ok=0
        printf '  %s：未報錯 / did not fail\n' "$label" >&2
        return
    fi
    # 只看結束碼分不出「拒絕」與「找不到刪除記錄」——放寬後的解析會落到後者，而那
    # 也是 exit 1。實測：把守衛換成 `if [ $# -gt 0 ]`，只驗結束碼的版本 94/94 全綠。
    # 所以理由本身必須比對。
    # Exit status alone cannot tell a refusal from "no matching deletion record":
    # a widened parse lands on the latter, which is also exit 1. Measured -- with
    # the guard replaced by `if [ $# -gt 0 ]`, the status-only version of this test
    # stayed 94/94 green. So the reason itself has to be compared.
    if ! printf '%s\n' "$out" | grep -q "requires an argument"; then
        restore_contract_ok=0
        printf '  %s：報錯理由不是「缺少引數」/ wrong reason: %s\n' \
            "$label" "$(printf '%s' "$out" | tr -d '\033' | tr '\n' ' ')" >&2
    fi
}

test_item "--restore 的引數契約沒有被 -- 放寬"
# 反套套邏輯：加的是終止符，不是「什麼都當成引數」。缺引數、-- 後面沒有東西、
# 誤打成另一個選項，以及含空白的破折號開頭引數，都必須照舊以「缺少引數」報錯。
# 除了理由，這裡還看得到放寬的直接後果：垃圾桶裡先種一筆「名字就叫 -f」的紀錄，
# 放寬後的解析會把 -f 當成要還原的檔名（實測 exit 0、檔案回到工作目錄、沒有任何
# 訊息）。因此「-f 沒有被還原」是這條契約的實質後果，不只是結束碼。
# 最後再證明那筆紀錄真的可用，否則「沒有被還原」可能只是因為根本沒東西可還原。
# Anti-tautology: what was added is the terminator, not "accept anything as the
# argument". A missing argument, a bare terminator with nothing after it, a
# mistyped option, and a dash-leading argument containing a space must all still
# fail with the missing-argument refusal.
# Beyond the reason, the consequence is observable: a record whose name is
# literally -f is seeded in the trash first, and a widened parse takes -f as the
# name to restore (measured: exit 0, the file back in the working directory, no
# message at all). "-f was not restored" is therefore a real consequence of this
# contract, not just an exit code.
# The seeded record is then proved live, or "was not restored" could simply mean
# there was nothing there to restore.
setup
cd "$TEST_WORK_DIR"
printf '%s\n' "SEEDED DASH F" > ./-f
"$BETTER_RM" -- -f >/dev/null 2>&1
restore_contract_ok=1
check_restore_refusal "--restore（沒有引數）" --restore
check_restore_refusal "--restore --（後面沒有東西）" --restore --
check_restore_refusal "--restore -f（沒有 --）" --restore -f
check_restore_refusal "--restore '-f oops.txt'（含空白）" --restore "-f oops.txt"
if [ -e ./-f ]; then
    restore_contract_ok=0
    printf '  被拒絕的呼叫卻把 -f 還原了 / a refused invocation restored -f\n' >&2
fi
seeded_restore_status=0
"$BETTER_RM" --restore -- -f >/dev/null 2>&1 || seeded_restore_status=$?
if [ "$seeded_restore_status" -ne 0 ] || [ ! -f ./-f ] || \
   [ "$(cat ./-f)" != "SEEDED DASH F" ]; then
    restore_contract_ok=0
    printf '  種下的 -f 紀錄不可用，上面的「沒有被還原」等於沒驗到 / the seeded -f record was not live (status=%s)\n' \
        "$seeded_restore_status" >&2
fi
if [ "$restore_contract_ok" -eq 1 ]; then
    test_pass "--restore 缺引數／裸 --／誤打選項／含空白選項仍以「缺少引數」拒絕"
else
    test_fail "--restore 的引數契約被放寬了"
fi

test_item "--restore -- 之後多出來的引數要被拒絕"
# 刪除端的 -- 吃掉「所有」剩下的引數，還原端只吃「一個」，兩邊範圍不同。多出來的
# 那個以前會被當成選項：實測 `rm --restore -- victim.txt -f` 結束碼 0，目的地被無
# 提示地換掉，而且垃圾桶裡一筆紀錄都沒有（那份內容直接沒了）。使用者看到的說明卻
# 寫著「-- 之後都是檔名」。
# 默默丟掉（`--restore -- a b` 的舊行為）同樣不行：還原路徑上「安靜地不照你說的做」
# 是最糟的失敗模式，拒絕才是保守方向。
# The delete side's -- consumes ALL remaining arguments; the restore side consumes
# exactly ONE. The extra used to be parsed as an option: measured,
# `rm --restore -- victim.txt -f` exited 0, replaced the destination with no
# prompt, and left zero trash entries -- that content was simply gone -- while the
# documentation told the user everything after -- was a pathname.
# Silently dropping it (the old `--restore -- a b` behaviour) is no better: quietly
# not doing what you were told is the worst failure mode on a restore path, and
# refusing is the conservative direction.
restore_scope_ok=1
setup
cd "$TEST_WORK_DIR"
printf '%s\n' "TRASHED VERSION" > scope_flag.txt
"$BETTER_RM" scope_flag.txt >/dev/null 2>&1
printf '%s\n' "PRECIOUS OCCUPANT" > scope_flag.txt
scope_flag_status=0
"$BETTER_RM" --restore -- scope_flag.txt -f </dev/null >/dev/null 2>&1 || scope_flag_status=$?
if [ "$scope_flag_status" -eq 0 ] || [ "$(cat scope_flag.txt)" != "PRECIOUS OCCUPANT" ]; then
    restore_scope_ok=0
    printf '  尾隨的 -f 未被拒絕 / trailing -f was not refused (status=%s, 目的地=%s)\n' \
        "$scope_flag_status" "$(cat scope_flag.txt)" >&2
fi

setup
cd "$TEST_WORK_DIR"
printf '%s\n' "TRASHED VERSION" > scope_extra.txt
"$BETTER_RM" scope_extra.txt >/dev/null 2>&1
printf '%s\n' "PRECIOUS OCCUPANT" > scope_extra.txt
scope_extra_status=0
"$BETTER_RM" --restore -- scope_extra.txt second.txt </dev/null >/dev/null 2>&1 || scope_extra_status=$?
if [ "$scope_extra_status" -eq 0 ] || [ "$(cat scope_extra.txt)" != "PRECIOUS OCCUPANT" ]; then
    restore_scope_ok=0
    printf '  尾隨的第二個檔名未被拒絕 / a trailing second pathname was not refused (status=%s)\n' \
        "$scope_extra_status" >&2
fi

# 反套套邏輯：拒絕的是 -- 之後多出來的引數，不是「--restore 不能跟旗標一起用」。
# 旗標寫在 --restore 前面（README 記載的寫法）必須照舊生效，含強制覆蓋。
# Anti-tautology: what is refused is a trailing argument after --, not "--restore
# cannot be combined with a flag". A flag placed before --restore -- the spelling
# the README documents -- must keep working, force-overwrite included.
setup
cd "$TEST_WORK_DIR"
printf '%s\n' "TRASHED VERSION" > scope_force.txt
"$BETTER_RM" scope_force.txt >/dev/null 2>&1
printf '%s\n' "PRECIOUS OCCUPANT" > scope_force.txt
scope_force_status=0
"$BETTER_RM" -f --restore -- scope_force.txt </dev/null >/dev/null 2>&1 || scope_force_status=$?
if [ "$scope_force_status" -ne 0 ] || [ "$(cat scope_force.txt)" != "TRASHED VERSION" ]; then
    restore_scope_ok=0
    printf '  -f 寫在 --restore 前面卻失效 / -f before --restore stopped working (status=%s, 目的地=%s)\n' \
        "$scope_force_status" "$(cat scope_force.txt)" >&2
fi

if [ "$restore_scope_ok" -eq 1 ]; then
    test_pass "-- 之後多出來的引數被拒絕，--restore 前面的旗標照舊生效"
else
    test_fail "--restore -- 的引數範圍不正確"
fi

# ============================================================================
# 測試 9: 受保護目錄 (Test 9: Protected Directories)
# ============================================================================
test_title "測試 9: 受保護目錄"

test_item "拒絕刪除根目錄 (/)"
if "$BETTER_RM" -rf / 2>&1 | grep -q "拒絕刪除受保護的目錄"; then
    test_pass "正確拒絕刪除根目錄"
else
    test_fail "未正確保護根目錄"
fi

test_item "拒絕刪除 /home"
if "$BETTER_RM" -rf /home 2>&1 | grep -q "拒絕刪除受保護的目錄"; then
    test_pass "正確拒絕刪除 /home"
else
    test_fail "未正確保護 /home"
fi

test_item "拒絕刪除 /mnt 與第一層掛載根"
mnt_protected=true
for protected_mnt_path in /mnt /mnt/c /mnt/../mnt/wsl; do
    if ! "$BETTER_RM" -rf "$protected_mnt_path" 2>&1 | grep -q "拒絕刪除受保護的目錄"; then
        mnt_protected=false
    fi
done
if [ "$mnt_protected" = true ]; then
    test_pass "正確保護 /mnt 與第一層掛載根"
else
    test_fail "未正確保護 /mnt 掛載根"
fi

test_item "允許處理 /mnt 掛載根內的一般路徑"
if "$BETTER_RM" -f /mnt/c/project/nonexistent 2>&1 | grep -q "拒絕刪除受保護的目錄"; then
    test_fail "錯誤封鎖 /mnt 掛載根內的一般路徑"
else
    test_pass "未封鎖 /mnt 掛載根內的一般路徑"
fi

test_item "拒絕刪除 .git 目錄"
setup
cd "$TEST_WORK_DIR"
mkdir -p project/.git
if "$BETTER_RM" -rf project/.git 2>&1 | grep -q "拒絕刪除受保護的目錄"; then
    test_pass "正確拒絕刪除 .git 目錄"
else
    test_fail "未正確保護 .git 目錄"
fi

# ============================================================================
# 測試 10: 快速連續刪除 (Test 10: Rapid Successive Deletions)
# ============================================================================
test_title "測試 10: 快速連續刪除（測試奈秒時間戳記）"

setup
cd "$TEST_WORK_DIR"

test_item "快速連續刪除多個檔案"
for i in {1..5}; do
    echo "content $i" > "rapid$i.txt"
done

for i in {1..5}; do
    "$BETTER_RM" "rapid$i.txt" &
done
wait

# 檢查所有檔案是否都成功刪除
all_deleted=true
for i in {1..5}; do
    if [ -e "rapid$i.txt" ]; then
        all_deleted=false
    fi
done

# 檢查是否有檔名衝突
trash_files=$(find "$TEST_TRASH_DIR" -name "rapid*.txt__*" 2>/dev/null | wc -l)

if $all_deleted && [ "$trash_files" -eq 5 ]; then
    test_pass "快速連續刪除成功，無檔名衝突（奈秒時間戳記正常工作）"
elif $all_deleted; then
    test_pass "快速連續刪除成功，但找到 $trash_files 個檔案（預期 5 個）"
else
    test_fail "快速連續刪除失敗"
fi

test_item "來源 parent 在 hash 期間被替換時不會移動替身檔案"
setup
cd "$TEST_WORK_DIR" || exit 1
source_parent_race_bin="$TEST_WORK_DIR/source-parent-race-bin"
mkdir -p "$source_parent_race_bin" source-parent victim-parent
cat > "$source_parent_race_bin/md5sum" <<'EOF'
#!/bin/sh
if [ ! -e "$BETTER_RM_SOURCE_PARENT_RACE_FLAG" ]; then
    : > "$BETTER_RM_SOURCE_PARENT_RACE_FLAG"
    "$BETTER_RM_REAL_MV" "$BETTER_RM_SOURCE_PARENT" \
        "$BETTER_RM_ORIGINAL_PARENT"
    ln -s "$BETTER_RM_VICTIM_PARENT" "$BETTER_RM_SOURCE_PARENT"
fi
exec "$BETTER_RM_REAL_MD5SUM" "$@"
EOF
chmod +x "$source_parent_race_bin/md5sum"

printf '%s\n' "ORIGINAL SOURCE" > source-parent/entry.txt
printf '%s\n' "VICTIM SOURCE" > victim-parent/entry.txt
source_parent_race_status=0
BETTER_RM_SOURCE_PARENT_RACE_FLAG="$TEST_WORK_DIR/source-parent-race-injected" \
BETTER_RM_SOURCE_PARENT="$TEST_WORK_DIR/source-parent" \
BETTER_RM_ORIGINAL_PARENT="$TEST_WORK_DIR/source-parent-original" \
BETTER_RM_VICTIM_PARENT="$TEST_WORK_DIR/victim-parent" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_MD5SUM="$(command -v md5sum)" \
PATH="$source_parent_race_bin:$PATH" \
    "$BETTER_RM" source-parent/entry.txt \
    >"$TEST_WORK_DIR/source-parent-race.out" 2>&1 ||
    source_parent_race_status=$?

original_source_entries=$(find "$TEST_TRASH_DIR" -type f -name "entry.txt__*" \
    -exec grep -lFx "ORIGINAL SOURCE" {} + 2>/dev/null | wc -l | tr -d ' ')
logged_source_parent_target=$(tail -n 1 "$TEST_STATE_DIR/deletion.log" 2>/dev/null |
    awk -F ' \\| ' '{print $4}')
if [ "$source_parent_race_status" -eq 0 ] && \
   [ -L "$TEST_WORK_DIR/source-parent" ] && \
   [ -f "$TEST_WORK_DIR/victim-parent/entry.txt" ] && \
   grep -qFx "VICTIM SOURCE" "$TEST_WORK_DIR/victim-parent/entry.txt" && \
   [ ! -e "$TEST_WORK_DIR/source-parent-original/entry.txt" ] && \
   [ "$original_source_entries" -eq 1 ] && \
   [ -f "$logged_source_parent_target" ] && \
   grep -qFx "ORIGINAL SOURCE" "$logged_source_parent_target"; then
    test_pass "來源 parent 被替換後仍只移動原始來源，victim 未受影響"
else
    test_fail "來源 parent 替換競態移動了 victim、遺失原始來源或寫入錯誤日誌"
fi

test_item "來源 entry 在 hash 後被替換時 fail closed"
setup
cd "$TEST_WORK_DIR" || exit 1
entry_race_bin="$TEST_WORK_DIR/entry-race-bin"
mkdir -p "$entry_race_bin"
cat > "$entry_race_bin/md5sum" <<'EOF'
#!/bin/sh
hash_output=$("$BETTER_RM_REAL_MD5SUM" "$@") || exit $?
if [ ! -e "$BETTER_RM_ENTRY_RACE_FLAG" ]; then
    : > "$BETTER_RM_ENTRY_RACE_FLAG"
    "$BETTER_RM_REAL_MV" "$BETTER_RM_ENTRY_SOURCE" \
        "$BETTER_RM_ENTRY_ORIGINAL"
    "$BETTER_RM_REAL_MV" "$BETTER_RM_ENTRY_VICTIM" \
        "$BETTER_RM_ENTRY_SOURCE"
fi
printf '%s\n' "$hash_output"
EOF
chmod +x "$entry_race_bin/md5sum"

printf '%s\n' "ORIGINAL ENTRY" > entry-race.txt
printf '%s\n' "VICTIM ENTRY" > entry-victim.txt
entry_race_status=0
BETTER_RM_ENTRY_RACE_FLAG="$TEST_WORK_DIR/entry-race-injected" \
BETTER_RM_ENTRY_SOURCE="$TEST_WORK_DIR/entry-race.txt" \
BETTER_RM_ENTRY_ORIGINAL="$TEST_WORK_DIR/entry-original.txt" \
BETTER_RM_ENTRY_VICTIM="$TEST_WORK_DIR/entry-victim.txt" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_MD5SUM="$(command -v md5sum)" \
PATH="$entry_race_bin:$PATH" \
    "$BETTER_RM" entry-race.txt >"$TEST_WORK_DIR/entry-race.out" 2>&1 ||
    entry_race_status=$?

if [ "$entry_race_status" -ne 0 ] && \
   [ -f entry-original.txt ] && grep -qFx "ORIGINAL ENTRY" entry-original.txt && \
   [ -f entry-race.txt ] && grep -qFx "VICTIM ENTRY" entry-race.txt && \
   [ ! -s "$TEST_STATE_DIR/deletion.log" ] && \
   ! find "$TEST_TRASH_DIR" -type f -name "entry-race.txt__*" 2>/dev/null | grep -q .; then
    test_pass "hash 後 entry 身分改變時停止，原始與 replacement 都保留"
else
    test_fail "hash 後 entry 身分改變仍移動 replacement、遺失來源或寫入日誌"
fi

test_item "相同路徑、內容與時間戳記不覆蓋既有垃圾桶項目"
setup
cd "$TEST_WORK_DIR" || exit 1
fixed_bin="$TEST_WORK_DIR/fixed-bin"
mkdir -p "$fixed_bin"
cat > "$fixed_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
chmod +x "$fixed_bin/date"

printf '%s\n' "same content" > collision.txt
PATH="$fixed_bin:$PATH" "$BETTER_RM" collision.txt
printf '%s\n' "same content" > collision.txt
PATH="$fixed_bin:$PATH" "$BETTER_RM" collision.txt

collision_entries=$(find "$TEST_TRASH_DIR" -name "collision.txt__*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ ! -e collision.txt ] && [ "$collision_entries" -eq 2 ]; then
    test_pass "碰撞時保留兩份可恢復項目"
else
    test_fail "碰撞覆蓋了既有垃圾桶項目（找到 $collision_entries，預期 2）"
fi

test_item "保留後才出現的垃圾桶項目不會被覆蓋"
setup
cd "$TEST_WORK_DIR" || exit 1
race_bin="$TEST_WORK_DIR/race-bin"
mkdir -p "$race_bin"
cat > "$race_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
cat > "$race_bin/mv" <<'EOF'
#!/bin/sh
target=""
for arg in "$@"; do
    target="$arg"
done
if [ ! -e "$BETTER_RM_RACE_FLAG" ]; then
    : > "$BETTER_RM_RACE_FLAG"
    printf '%s\n' "OLDER RECOVERY ENTRY" > "$target"
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$race_bin/date" "$race_bin/mv"

printf '%s\n' "NEW SOURCE ENTRY" > late-collision.txt
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_RACE_FLAG="$TEST_WORK_DIR/race-injected" \
PATH="$race_bin:$PATH" \
    "$BETTER_RM" late-collision.txt

late_entries=$(find "$TEST_TRASH_DIR" -name "late-collision.txt__*" -type f 2>/dev/null | wc -l | tr -d ' ')
older_entries=$(find "$TEST_TRASH_DIR" -name "late-collision.txt__*" -type f \
    -exec grep -lFx "OLDER RECOVERY ENTRY" {} + 2>/dev/null | wc -l | tr -d ' ')
new_entries=$(find "$TEST_TRASH_DIR" -name "late-collision.txt__*" -type f \
    -exec grep -lFx "NEW SOURCE ENTRY" {} + 2>/dev/null | wc -l | tr -d ' ')
if [ ! -e late-collision.txt ] && [ "$late_entries" -eq 2 ] && \
   [ "$older_entries" -eq 1 ] && [ "$new_entries" -eq 1 ]; then
    test_pass "晚到的垃圾桶項目與新來源都保留"
else
    test_fail "晚到項目被覆蓋或來源未安全轉移"
fi

test_item "晚到的同名目錄不會吞入來源，且 suffixed recovery 可還原"
setup
cd "$TEST_WORK_DIR" || exit 1
directory_race_bin="$TEST_WORK_DIR/directory-race-bin"
mkdir -p "$directory_race_bin"
cat > "$directory_race_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
cat > "$directory_race_bin/mv" <<'EOF'
#!/bin/sh
target=""
for arg in "$@"; do
    target="$arg"
done
if [ ! -e "$BETTER_RM_RACE_FLAG" ]; then
    : > "$BETTER_RM_RACE_FLAG"
    mkdir -p "$target"
    printf '%s\n' "OLDER DIRECTORY ENTRY" > "$target/writer-marker.txt"
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$directory_race_bin/date" "$directory_race_bin/mv"

printf '%s\n' "NEW SOURCE ENTRY" > late-directory.txt
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_RACE_FLAG="$TEST_WORK_DIR/directory-race-injected" \
PATH="$directory_race_bin:$PATH" \
    "$BETTER_RM" late-directory.txt

old_directory_entries=$(find "$TEST_TRASH_DIR" -type f -name writer-marker.txt \
    -exec grep -lFx "OLDER DIRECTORY ENTRY" {} + 2>/dev/null | wc -l | tr -d ' ')
new_directory_race_entries=$(find "$TEST_TRASH_DIR" -type f -name "late-directory.txt__*" \
    -exec grep -lFx "NEW SOURCE ENTRY" {} + 2>/dev/null | wc -l | tr -d ' ')
nested_source_entries=$(find "$TEST_TRASH_DIR" -type f -name late-directory.txt \
    -path "*/late-directory.txt__*/*" 2>/dev/null | wc -l | tr -d ' ')
logged_directory_race_target=$(tail -n 1 "$TEST_STATE_DIR/deletion.log" |
    awk -F ' \\| ' '{print $4}')

collision_safe=false
if [ ! -e late-directory.txt ] && [ "$old_directory_entries" -eq 1 ] && \
   [ "$new_directory_race_entries" -eq 1 ] && [ "$nested_source_entries" -eq 0 ] && \
   [ -f "$logged_directory_race_target" ] && \
   grep -qFx "NEW SOURCE ENTRY" "$logged_directory_race_target"; then
    collision_safe=true
fi

restore_safe=false
if [ "$collision_safe" = true ] &&
   "$BETTER_RM" --restore late-directory.txt >/dev/null 2>&1 &&
   [ -f late-directory.txt ] &&
   grep -qFx "NEW SOURCE ENTRY" late-directory.txt; then
    old_directory_entries_after_restore=$(find "$TEST_TRASH_DIR" -type f -name writer-marker.txt \
        -exec grep -lFx "OLDER DIRECTORY ENTRY" {} + 2>/dev/null | wc -l | tr -d ' ')
    if [ "$old_directory_entries_after_restore" -eq 1 ]; then
        restore_safe=true
    fi
fi

if [ "$collision_safe" = true ] && [ "$restore_safe" = true ]; then
    test_pass "晚到目錄保留，來源移至獨立 recovery path 並可由新日誌還原"
else
    test_fail "晚到目錄吞入來源、日誌錯指，或 suffixed recovery 無法還原"
fi

test_item "rollback 路徑遭同名目錄佔用時保留原始 inode 並 fail closed"
setup
cd "$TEST_WORK_DIR" || exit 1
rollback_race_bin="$TEST_WORK_DIR/rollback-race-bin"
mkdir -p "$rollback_race_bin"
cat > "$rollback_race_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
cat > "$rollback_race_bin/mv" <<'EOF'
#!/bin/sh
count=0
if [ -f "$BETTER_RM_RACE_FLAG" ]; then
    count=$(sed -n '1p' "$BETTER_RM_RACE_FLAG")
fi
count=$((count + 1))
printf '%s\n' "$count" > "$BETTER_RM_RACE_FLAG"

while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do
    shift
done
source_arg="$1"
target_arg="$2"

case "$count" in
    1)
        mkdir -p "$target_arg"
        printf '%s\n' "OLDER DIRECTORY ENTRY" > "$target_arg/writer-marker.txt"
        exec "$BETTER_RM_REAL_MV" "$source_arg" \
            "$target_arg/$(basename "$source_arg")"
        ;;
    2)
        mkdir -p "$target_arg"
        printf '%s\n' "ATTACKER SOURCE DIRECTORY" > "$target_arg/attacker-marker.txt"
        exec "$BETTER_RM_REAL_MV" "$source_arg" \
            "$target_arg/$(basename "$source_arg")"
        ;;
    *)
        exec "$BETTER_RM_REAL_MV" "$source_arg" "$target_arg"
        ;;
esac
EOF
chmod +x "$rollback_race_bin/date" "$rollback_race_bin/mv"

printf '%s\n' "ORIGINAL ROLLBACK SOURCE" > rollback-race.txt
rollback_race_status=0
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_RACE_FLAG="$TEST_WORK_DIR/rollback-race-count" \
PATH="$rollback_race_bin:$PATH" \
    "$BETTER_RM" rollback-race.txt >"$TEST_WORK_DIR/rollback-race.out" 2>&1 ||
    rollback_race_status=$?

rollback_recovery_path="$TEST_WORK_DIR/rollback-race.txt/rollback-race.txt"
# 斷言走的是「rollback 身分不符」這條 fail-closed 分支（而非通用的
# 「無法確認垃圾桶位置」分支），以固定 better-rm:544 的相等判斷。
# Pin the dedicated inode-preservation branch by asserting its distinctive
# message, so inverting the identity guard at better-rm:544 is caught.
if [ "$rollback_race_status" -ne 0 ] && \
   [ -f "$rollback_recovery_path" ] && \
   grep -qFx "ORIGINAL ROLLBACK SOURCE" "$rollback_recovery_path" && \
   [ -f "$TEST_WORK_DIR/rollback-race.txt/attacker-marker.txt" ] && \
   grep -q "Rollback identity mismatch" "$TEST_WORK_DIR/rollback-race.out" && \
   [ ! -s "$TEST_STATE_DIR/deletion.log" ]; then
    test_pass "rollback 身分不符時停止、保留精確 recovery path 且不寫入誤導日誌"
else
    test_fail "rollback 身分不符仍移走攻擊者目錄、遺失原始 inode 或寫入誤導日誌"
fi

test_item "晚到的 symlink-to-directory 不會把來源移出垃圾桶命名空間"
setup
cd "$TEST_WORK_DIR" || exit 1
symlink_race_bin="$TEST_WORK_DIR/symlink-race-bin"
mkdir -p "$symlink_race_bin"
cat > "$symlink_race_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
cat > "$symlink_race_bin/mv" <<'EOF'
#!/bin/sh
target=""
for arg in "$@"; do
    target="$arg"
done
if [ ! -e "$BETTER_RM_RACE_FLAG" ]; then
    : > "$BETTER_RM_RACE_FLAG"
    mkdir -p "$BETTER_RM_SYMLINK_DIR"
    ln -s "$BETTER_RM_SYMLINK_DIR" "$target"
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$symlink_race_bin/date" "$symlink_race_bin/mv"

printf '%s\n' "NEW SYMLINK-RACE SOURCE" > late-symlink.txt
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_RACE_FLAG="$TEST_WORK_DIR/symlink-race-injected" \
BETTER_RM_SYMLINK_DIR="$TEST_WORK_DIR/attacker-directory" \
PATH="$symlink_race_bin:$PATH" \
    "$BETTER_RM" late-symlink.txt

symlink_race_links=$(find "$TEST_TRASH_DIR" -type l -name "late-symlink.txt__*" \
    2>/dev/null | wc -l | tr -d ' ')
symlink_race_entries=$(find "$TEST_TRASH_DIR" -type f -name "late-symlink.txt__*" \
    -exec grep -lFx "NEW SYMLINK-RACE SOURCE" {} + 2>/dev/null | wc -l | tr -d ' ')
logged_symlink_race_target=$(tail -n 1 "$TEST_STATE_DIR/deletion.log" |
    awk -F ' \\| ' '{print $4}')
if [ ! -e late-symlink.txt ] && [ "$symlink_race_links" -eq 1 ] && \
   [ "$symlink_race_entries" -eq 1 ] && \
   [ ! -e "$TEST_WORK_DIR/attacker-directory/late-symlink.txt" ] && \
   [ -f "$logged_symlink_race_target" ] && \
   grep -qFx "NEW SYMLINK-RACE SOURCE" "$logged_symlink_race_target"; then
    test_pass "symlink race 未被跟隨，來源改存於獨立且正確記錄的 recovery path"
else
    test_fail "symlink race 將來源移入攻擊者目錄或記錄了錯誤 recovery path"
fi

test_item "實際目錄來源在晚到目錄競態下以 inode 身分安全復原"
setup
cd "$TEST_WORK_DIR" || exit 1
directory_source_race_bin="$TEST_WORK_DIR/directory-source-race-bin"
mkdir -p "$directory_source_race_bin"
cat > "$directory_source_race_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
cat > "$directory_source_race_bin/mv" <<'EOF'
#!/bin/sh
target=""
for arg in "$@"; do
    target="$arg"
done
if [ ! -e "$BETTER_RM_RACE_FLAG" ]; then
    : > "$BETTER_RM_RACE_FLAG"
    mkdir -p "$target"
    printf '%s\n' "OLDER DIRECTORY ENTRY" > "$target/writer-marker.txt"
fi
# Linux 的 -T 已於其他案例驗證；此 mock 去除它來模擬 BSD 目錄容器語意。
# Linux -T is covered elsewhere; strip it here to emulate BSD directory-container semantics.
if [ "$1" = "-n" ] && [ "$2" = "-T" ]; then
    shift 2
    exec "$BETTER_RM_REAL_MV" -n "$@"
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$directory_source_race_bin/date" "$directory_source_race_bin/mv"

mkdir late-directory-source
printf '%s\n' "NEW DIRECTORY SOURCE" > late-directory-source/payload.txt
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_RACE_FLAG="$TEST_WORK_DIR/directory-source-race-injected" \
PATH="$directory_source_race_bin:$PATH" \
    "$BETTER_RM" -r late-directory-source

old_directory_source_entries=$(find "$TEST_TRASH_DIR" -type f -name writer-marker.txt \
    -exec grep -lFx "OLDER DIRECTORY ENTRY" {} + 2>/dev/null | wc -l | tr -d ' ')
new_directory_source_entries=$(find "$TEST_TRASH_DIR" -type f -name payload.txt \
    -path "*late-directory-source__*/*" -exec grep -lFx "NEW DIRECTORY SOURCE" {} + \
    2>/dev/null | wc -l | tr -d ' ')
nested_directory_source_entries=$(find "$TEST_TRASH_DIR" -type f -name payload.txt \
    -path "*late-directory-source__*/late-directory-source/*" 2>/dev/null | wc -l | tr -d ' ')
if [ ! -e late-directory-source ] && [ "$old_directory_source_entries" -eq 1 ] && \
   [ "$new_directory_source_entries" -eq 1 ] && [ "$nested_directory_source_entries" -eq 0 ]; then
    test_pass "實際目錄來源以 inode 辨識容器競態並移至獨立 recovery path"
else
    test_fail "實際目錄來源未安全辨識容器競態或仍被巢狀存放"
fi

test_item "目錄 inode 無法取得時在 late-container move 前 fail closed"
setup
cd "$TEST_WORK_DIR" || exit 1
identity_failure_bin="$TEST_WORK_DIR/identity-failure-bin"
mkdir -p "$identity_failure_bin"
cat > "$identity_failure_bin/stat" <<'EOF'
#!/bin/sh
last_arg=""
for arg in "$@"; do
    last_arg="$arg"
done
if [ "$last_arg" = "$BETTER_RM_STAT_FAIL_PATH" ]; then
    exit 1
fi
exec "$BETTER_RM_REAL_STAT" "$@"
EOF
cat > "$identity_failure_bin/mv" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do
    shift
done
source_arg="$1"
target_arg="$2"
printf '%s\n' "move invoked" > "$BETTER_RM_MOVE_FLAG"
mkdir -p "$target_arg"
printf '%s\n' "LATE CONTAINER" > "$target_arg/writer-marker.txt"
exec "$BETTER_RM_REAL_MV" "$source_arg" \
    "$target_arg/$(basename "$source_arg")"
EOF
chmod +x "$identity_failure_bin/stat" "$identity_failure_bin/mv"

mkdir -p late-identity-directory/late-identity-directory
printf '%s\n' "ORIGINAL DIRECTORY" > late-identity-directory/payload.txt
printf '%s\n' "ORIGINAL SAME-NAME CHILD" \
    > late-identity-directory/late-identity-directory/child.txt
identity_failure_status=0
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_STAT_FAIL_PATH="late-identity-directory" \
BETTER_RM_MOVE_FLAG="$TEST_WORK_DIR/identity-failure-move-invoked" \
PATH="$identity_failure_bin:$PATH" \
    "$BETTER_RM" -r late-identity-directory \
    >"$TEST_WORK_DIR/identity-failure.out" 2>&1 ||
    identity_failure_status=$?

if [ "$identity_failure_status" -ne 0 ] && \
   [ -f late-identity-directory/payload.txt ] && \
   [ -f late-identity-directory/late-identity-directory/child.txt ] && \
   [ ! -e "$TEST_WORK_DIR/identity-failure-move-invoked" ] && \
   [ ! -s "$TEST_STATE_DIR/deletion.log" ]; then
    test_pass "目錄身分不可驗證時保留完整來源、未移動且未寫入日誌"
else
    test_fail "目錄身分不可驗證時仍進入 move、遺失來源或寫入誤導日誌"
fi

# ============================================================================
# 測試 11: 路徑結構保留 (Test 11: Path Structure Preservation)
# ============================================================================
test_title "測試 11: 垃圾桶路徑結構保留"

setup
cd "$TEST_WORK_DIR"

test_item "深層目錄結構保留"
mkdir -p deep/nested/directory/structure
echo "deep content" > deep/nested/directory/structure/file.txt
original_path="$TEST_WORK_DIR/deep/nested/directory/structure/file.txt"
"$BETTER_RM" deep/nested/directory/structure/file.txt

# 檢查垃圾桶中是否保留了路徑結構 (考慮 macOS 的 /tmp -> /private/tmp)
resolved_work_dir=$(readlink -f "$TEST_WORK_DIR" 2>/dev/null || realpath "$TEST_WORK_DIR" 2>/dev/null || echo "$TEST_WORK_DIR")
if find "$TEST_TRASH_DIR$resolved_work_dir/deep/nested/directory/structure" -name "file.txt__*" | grep -q .; then
    test_pass "路徑結構成功保留"
else
    test_fail "路徑結構未保留"
fi

# ============================================================================
# 測試 12: 自訂垃圾桶目錄 (Test 12: Custom Trash Directory)
# ============================================================================
test_title "測試 12: 自訂垃圾桶目錄"

test_item "使用自訂 TRASH_DIR"
custom_trash="/tmp/custom-trash-test"
rm -rf "$custom_trash"
cd "$TEST_WORK_DIR"
echo "custom trash test" > customtest.txt

TRASH_DIR="$custom_trash" "$BETTER_RM" customtest.txt

if [ -d "$custom_trash" ] && find "$custom_trash" -name "customtest.txt__*" | grep -q . && \
   [ ! -e "$custom_trash/.deletion_log" ] && verify_log_entry "customtest.txt"; then
    test_pass "自訂垃圾桶目錄正常工作"
else
    test_fail "自訂垃圾桶目錄失敗"
fi
rm -rf "$custom_trash"

test_item "使用自訂 BETTER_RM_STATE_DIR"
custom_state="/tmp/custom-better-rm-state-test"
rm -rf "$custom_state"
echo "custom state test" > customstatetest.txt
BETTER_RM_STATE_DIR="$custom_state" "$BETTER_RM" customstatetest.txt
if [ -f "$custom_state/deletion.log" ] && grep -q "customstatetest.txt" "$custom_state/deletion.log"; then
    test_pass "自訂狀態目錄正常工作"
else
    test_fail "自訂狀態目錄失敗"
fi
rm -rf "$custom_state"

test_item "使用 XDG_STATE_HOME"
custom_xdg_state="/tmp/custom-xdg-state-test"
rm -rf "$custom_xdg_state"
echo "xdg state test" > xdgstatetest.txt
BETTER_RM_STATE_DIR="" XDG_STATE_HOME="$custom_xdg_state" "$BETTER_RM" xdgstatetest.txt
if [ -f "$custom_xdg_state/better-rm/deletion.log" ] && \
   grep -q "xdgstatetest.txt" "$custom_xdg_state/better-rm/deletion.log"; then
    test_pass "XDG 狀態目錄正常工作"
else
    test_fail "XDG 狀態目錄失敗"
fi
rm -rf "$custom_xdg_state"

test_item "相對 XDG_STATE_HOME 回退預設狀態目錄"
fallback_home="/tmp/better-rm-state-fallback-home"
rm -rf "$fallback_home"
mkdir -p "$fallback_home"
echo "fallback state test" > fallbackstatetest.txt
HOME="$fallback_home" BETTER_RM_STATE_DIR="" XDG_STATE_HOME="relative-state" \
    "$BETTER_RM" fallbackstatetest.txt
if [ -f "$fallback_home/.local/state/better-rm/deletion.log" ] && \
   grep -q "fallbackstatetest.txt" "$fallback_home/.local/state/better-rm/deletion.log"; then
    test_pass "相對 XDG_STATE_HOME 正確回退"
else
    test_fail "相對 XDG_STATE_HOME 未正確回退"
fi
rm -rf "$fallback_home"

# ============================================================================
# 測試 13: 還原功能 (Test 13: Restore Function)
# ============================================================================
test_title "測試 13: 還原功能"

test_item "基本還原功能"
cd "$TEST_WORK_DIR"
echo "original content" > test_restore.txt
"$BETTER_RM" test_restore.txt

if [ -f "test_restore.txt" ]; then
    test_fail "測試還原前的刪除失敗"
else
    # 執行還原
    "$BETTER_RM" --restore test_restore.txt
    if [ -f "test_restore.txt" ] && [ "$(cat test_restore.txt)" = "original content" ]; then
        test_pass "基本還原成功"
    else
        test_fail "基本還原失敗"
    fi
fi

test_item "再次還原（已不存在於垃圾桶）"
# 因為已經被還原移出，再次還原應提示找不到
if "$BETTER_RM" --restore test_restore.txt 2>/dev/null; then
    test_fail "不應成功還原已不在垃圾桶的檔案"
else
    test_pass "再次還原正確地回傳失敗"
fi

test_item "同名檔案存在時的覆蓋確認 - 選擇否 (n)"
echo "content v1" > test_restore.txt
"$BETTER_RM" test_restore.txt
echo "local content v2" > test_restore.txt

# 模擬使用者輸入 n
echo "n" | "$BETTER_RM" --restore test_restore.txt >/dev/null 2>&1
if [ "$(cat test_restore.txt)" = "local content v2" ]; then
    test_pass "選擇否 (n) 時未覆蓋同名檔案"
else
    test_fail "選擇否 (n) 時同名檔案被錯誤覆蓋"
fi

test_item "同名檔案存在時的覆蓋確認 - 選擇是 (y)"
# 模擬使用者輸入 y
echo "y" | "$BETTER_RM" --restore test_restore.txt >/dev/null 2>&1
if [ "$(cat test_restore.txt)" = "content v1" ]; then
    test_pass "選擇是 (y) 時成功覆蓋同名檔案"
else
    test_fail "選擇是 (y) 時同名檔案未被覆蓋"
fi

test_item "同名檔案存在時的 -f 強制覆蓋"
# 重新刪除並準備環境
echo "content v1" > test_restore.txt
"$BETTER_RM" test_restore.txt
echo "local content v3" > test_restore.txt

# 使用 -f 參數，不應提示確認且應直接覆蓋
"$BETTER_RM" -f --restore test_restore.txt >/dev/null 2>&1
if [ "$(cat test_restore.txt)" = "content v1" ]; then
    test_pass "-f 強制覆蓋同名檔案成功"
else
    test_fail "-f 強制覆蓋同名檔案失敗"
fi

test_item "新日誌無符合項目時回退舊版垃圾桶日誌"
setup
cd "$TEST_WORK_DIR"
echo "legacy content" > legacy_restore.txt
"$BETTER_RM" legacy_restore.txt
mv "$TEST_STATE_DIR/deletion.log" "$TEST_TRASH_DIR/.deletion_log"
echo "current content" > current_log_only.txt
"$BETTER_RM" current_log_only.txt
"$BETTER_RM" --restore legacy_restore.txt
if [ -f legacy_restore.txt ] && [ "$(cat legacy_restore.txt)" = "legacy content" ]; then
    test_pass "舊版垃圾桶日誌回退還原成功"
else
    test_fail "舊版垃圾桶日誌回退還原失敗"
fi

test_item "還原搬移失敗時不得先毀掉既有目的地"
# 覆蓋確認通過後若先 /bin/rm -rf 目的地再 mv，mv 失敗就等於同時失去
# 「本機既有檔案」與「還原」。搬移失敗必須讓兩邊都原封不動。
# Deleting the destination before the mv means a failed mv loses the existing
# local file AND the restore. A failed move must leave both sides untouched.
setup
cd "$TEST_WORK_DIR"
restore_fail_bin="$TEST_WORK_DIR/restore-fail-bin"
mkdir -p "$restore_fail_bin"
cat > "$restore_fail_bin/mv" <<'EOF'
#!/bin/sh
# 只讓「從垃圾桶搬回」這一步失敗，其餘 mv 照常執行。
for arg in "$@"; do
    case "$arg" in
        "$BETTER_RM_FAIL_MV_PREFIX"*)
            echo "mv: simulated failure" >&2
            exit 1
            ;;
    esac
done
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$restore_fail_bin/mv"

printf '%s\n' "TRASHED CONTENT" > restore_atomic.txt
"$BETTER_RM" restore_atomic.txt
printf '%s\n' "LOCAL CONTENT" > restore_atomic.txt
restore_trash_item=$(find "$TEST_TRASH_DIR" -type f -name "restore_atomic.txt__*" | head -1)
restore_fail_status=0
BETTER_RM_FAIL_MV_PREFIX="$TEST_TRASH_DIR" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$restore_fail_bin:$PATH" \
    "$BETTER_RM" -f --restore restore_atomic.txt >/dev/null 2>&1 ||
    restore_fail_status=$?

if [ "$restore_fail_status" -ne 0 ] && \
   [ -f restore_atomic.txt ] && \
   [ "$(cat restore_atomic.txt)" = "LOCAL CONTENT" ] && \
   [ -n "$restore_trash_item" ] && [ -f "$restore_trash_item" ] && \
   [ "$(cat "$restore_trash_item")" = "TRASHED CONTENT" ] && \
   [ -z "$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'restore_atomic.txt.better-rm-restore-*' 2>/dev/null)" ]; then
    test_pass "搬移失敗時目的地與垃圾桶項目都完好，且未殘留暫存檔"
else
    test_fail "搬移失敗時毀掉了既有目的地或垃圾桶項目 (status=$restore_fail_status)"
fi

test_item "還原：起初不存在、途中才出現的真目錄，連一次搬進去的嘗試都不可以有"
# 目的地在同意檢查時不存在，就沒有任何覆蓋授權；之後才出現的目錄不是合法的覆蓋對象。
# 只靠事後的 inode 驗證是不夠的：BSD mv 會把項目搬「進」那個目錄，事後再撈出來。撈得
# 回來是運氣，撈不回來（例如對方目錄隨即變成不可寫）項目就卡在別人的樹裡。因此契約
# 是「未經授權的目的地，連一次 mv 的落點都不可以是它」，shim 記錄每一次 mv 的落點來
# 驗證這件事。
# The destination did not exist at the consent check, so no overwrite was ever
# authorized and a directory appearing later is not a legal overwrite target.
# Verifying by inode afterwards is not enough: BSD mv moves the item INTO that
# directory and only then is it pulled back out. Getting it back is luck; if the
# newcomer's directory turns unwritable in between, the item is stranded inside
# someone else's tree. The contract is therefore "an unauthorized destination must
# never be the target of even one mv", and the shim records every mv target to
# prove it.
setup
cd "$TEST_WORK_DIR" || exit 1
late_dir_bin="$TEST_WORK_DIR/restore-late-dir-bin"
mkdir -p "$late_dir_bin"
cat > "$late_dir_bin/mv" <<'EOF'
#!/bin/sh
if [ ! -e "$BETTER_RM_LATE_MARKER" ]; then
    mkdir "$BETTER_RM_LATE_DEST" || exit 1
    printf '%s\n' "LATE DIRECTORY" > "$BETTER_RM_LATE_DEST/marker.txt"
    : > "$BETTER_RM_LATE_MARKER"
fi
for a in "$@"; do dst=$a; done
printf '%s\n' "$dst" >> "$BETTER_RM_LATE_TARGETS"
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$late_dir_bin/mv"

printf '%s\n' "TRASHED CONTENT" > late_dir_target.txt
"$BETTER_RM" late_dir_target.txt
late_dir_trash_item=$(find "$TEST_TRASH_DIR" -type f -name 'late_dir_target.txt__*' | head -1)
late_dir_status=0
BETTER_RM_LATE_MARKER="$TEST_WORK_DIR/late-dir-marker" \
BETTER_RM_LATE_DEST="$TEST_WORK_DIR/late_dir_target.txt" \
BETTER_RM_LATE_TARGETS="$TEST_WORK_DIR/late-dir-targets" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$late_dir_bin:$PATH" \
    "$BETTER_RM" --restore late_dir_target.txt >/dev/null 2>&1 ||
    late_dir_status=$?

late_displaced=$(find "$TEST_WORK_DIR" -name '.better-rm-displaced' -print -quit 2>/dev/null)
late_attempts=0
if [ -f "$TEST_WORK_DIR/late-dir-targets" ]; then
    late_attempts=$(grep -cxF "$TEST_WORK_DIR/late_dir_target.txt" \
        "$TEST_WORK_DIR/late-dir-targets" 2>/dev/null || true)
    late_attempts=${late_attempts:-0}
fi
if [ "$late_dir_status" -eq 1 ] && \
   [ -d late_dir_target.txt ] && \
   [ "$(cat late_dir_target.txt/marker.txt 2>/dev/null)" = "LATE DIRECTORY" ] && \
   [ -n "$late_dir_trash_item" ] && [ -f "$late_dir_trash_item" ] && \
   [ "$(cat "$late_dir_trash_item")" = "TRASHED CONTENT" ] && \
   [ "$late_attempts" -eq 0 ] && \
   [ -z "$late_displaced" ]; then
    test_pass "未經授權的目的地從未成為任何 mv 的落點，垃圾桶項目也完整放回"
else
    test_fail "途中出現的真目錄被當成落點或吞掉垃圾桶項目 (status=$late_dir_status, attempts=$late_attempts)"
fi

test_item "還原：所有檢查都通過後、就位前一刻才出現的真目錄仍不得被覆蓋"
# 比上一個測試更晚的窗口：目錄在「取出完成、前置存在性檢查也已通過」之後才出現，
# 就在 publish 的那一次 mv 之前。此時唯一還能擋住覆蓋的是 publish 用 -n 加上事後的
# inode 驗證。shim 只依「第 N 次 mv」動手，不依賴 better-rm 的任何內部命名。
# A strictly later window than the previous test: the directory appears after the
# extraction and after the existence gate has passed, immediately before the
# publishing mv. The only thing that can still prevent a clobber at that point is
# the -n publish plus the inode check after it. The shim keys off "the Nth mv"
# only, never on any internal naming.
setup
cd "$TEST_WORK_DIR" || exit 1
publish_bin="$TEST_WORK_DIR/restore-publish-bin"
mkdir -p "$publish_bin"
cat > "$publish_bin/mv" <<'EOF'
#!/bin/sh
n=$(cat "$BETTER_RM_PUBLISH_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" > "$BETTER_RM_PUBLISH_COUNT"
if [ "$n" -eq 2 ]; then
    mkdir "$BETTER_RM_PUBLISH_DEST" || exit 1
    printf '%s\n' "LATE DIRECTORY" > "$BETTER_RM_PUBLISH_DEST/marker.txt"
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$publish_bin/mv"

printf '%s\n' "TRASHED CONTENT" > publish_target.txt
"$BETTER_RM" publish_target.txt
publish_trash_item=$(find "$TEST_TRASH_DIR" -type f -name 'publish_target.txt__*' | head -1)
publish_status=0
BETTER_RM_PUBLISH_COUNT="$TEST_WORK_DIR/publish-count" \
BETTER_RM_PUBLISH_DEST="$TEST_WORK_DIR/publish_target.txt" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$publish_bin:$PATH" \
    "$BETTER_RM" --restore publish_target.txt >/dev/null 2>&1 ||
    publish_status=$?
publish_staging=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'publish_target.txt.better-rm-restore-*' -print -quit 2>/dev/null)

if [ "$publish_status" -eq 1 ] && \
   [ -d publish_target.txt ] && \
   [ "$(cat publish_target.txt/marker.txt 2>/dev/null)" = "LATE DIRECTORY" ] && \
   [ -n "$publish_trash_item" ] && [ -f "$publish_trash_item" ] && \
   [ "$(cat "$publish_trash_item")" = "TRASHED CONTENT" ] && \
   [ -z "$publish_staging" ]; then
    test_pass "publish 前一刻出現的目錄未被覆蓋，垃圾桶項目完整放回且不殘留 staging"
else
    test_fail "publish 前的競態覆蓋了新目錄、吞掉垃圾桶項目或留下 staging (status=$publish_status)"
fi

test_item "還原：已授權覆蓋時，讓位之後才出現的後繼者不在授權範圍內"
# 上一個測試走的是 dest_existed=0 的路（從來沒有授權）。這一個走的是相反那條：目的地
# 起初就在、使用者也同意覆蓋了，而那個被同意的東西已經讓位進垃圾桶。同意的對象是「還原
# 開始時佔著目的地的那一個物件」，不是「那條路徑」——讓位之後才被放上來的是另一個物件，
# 沒有人同意覆蓋它。
# 舊寫法把同意 latch 成 clobber_policy=-f 一路帶到 publish，於是 -f 唯一還能作用的對象
# 就只剩下這種後繼者：實測 exit 0、後繼者被 rename 原子地解除連結，垃圾桶裡沒有它、也
# 沒有備份。這一列就是那個差別——它必須 fail closed，兩邊的東西都要還在。
# The previous test takes the dest_existed=0 route, where nothing was ever
# authorized. This one takes the opposite route: the destination WAS there at the
# start and the user did consent to overwriting it, and that consented object has
# already been set aside into the trash. The consent names the object that
# occupied the destination when the restore began, not the path -- whatever is put
# there after the set-aside is a different object and nobody consented to it.
# The old shape latched the consent into clobber_policy=-f all the way to the
# publish, which left the successor as the only thing -f could still act on:
# measured exit 0 with the successor atomically unlinked by the rename, no trash
# entry, no backup. This row is that difference; it has to fail closed with both
# objects still present.
# shim 只看檔案系統狀態（目的地何時變空），不看 better-rm 的任何內部命名或 mv 序數。
# The shim keys only on filesystem state (when the destination becomes free),
# never on better-rm's internal naming or on an mv ordinal.
setup
cd "$TEST_WORK_DIR" || exit 1
successor_bin="$TEST_WORK_DIR/restore-successor-bin"
mkdir -p "$successor_bin"
cat > "$successor_bin/mv" <<'EOF'
#!/bin/sh
if [ ! -e "$BETTER_RM_SUCC_MARKER" ] &&
   [ ! -e "$BETTER_RM_SUCC_DEST" ] && [ ! -L "$BETTER_RM_SUCC_DEST" ]; then
    printf '%s\n' "SUCCESSOR" > "$BETTER_RM_SUCC_DEST"
    : > "$BETTER_RM_SUCC_MARKER"
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$successor_bin/mv"

printf '%s\n' "TRASHED CONTENT" > successor_target.txt
"$BETTER_RM" successor_target.txt
successor_trash_item=$(find "$TEST_TRASH_DIR" -type f -name 'successor_target.txt__*' | head -1)
# 目的地在還原開始時就存在，-f 就是使用者對「它」的覆蓋同意。
# The destination exists when the restore begins and -f is the user's consent to
# overwrite THAT object.
printf '%s\n' "ORIGINAL DESTINATION" > successor_target.txt
successor_status=0
BETTER_RM_SUCC_MARKER="$TEST_WORK_DIR/successor-marker" \
BETTER_RM_SUCC_DEST="$TEST_WORK_DIR/successor_target.txt" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$successor_bin:$PATH" \
    "$BETTER_RM" -f --restore successor_target.txt >/dev/null 2>&1 ||
    successor_status=$?
successor_staging=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'successor_target.txt.better-rm-restore-*' -print -quit 2>/dev/null)
# 讓位的舊目的地必須還在垃圾桶裡（可用 rm --restore 取回），被還原的項目也必須放回去，
# 所以垃圾桶裡是兩筆，而不是一筆。
# The displaced old destination must still be in the trash (recoverable with
# rm --restore) and the item being restored must have been put back, so the trash
# holds two entries, not one.
successor_trash_count=$(find "$TEST_TRASH_DIR" -type f -name 'successor_target.txt__*' | wc -l | tr -d ' ')

if [ "$successor_status" -eq 1 ] && \
   [ -f successor_target.txt ] && [ ! -L successor_target.txt ] && \
   [ "$(cat successor_target.txt 2>/dev/null)" = "SUCCESSOR" ] && \
   [ -e "$TEST_WORK_DIR/successor-marker" ] && \
   [ -n "$successor_trash_item" ] && [ -f "$successor_trash_item" ] && \
   [ "$(cat "$successor_trash_item")" = "TRASHED CONTENT" ] && \
   [ "$successor_trash_count" -eq 2 ] && \
   [ -z "$successor_staging" ]; then
    test_pass "讓位後才出現的後繼者未被授權覆蓋掉，舊目的地與垃圾桶項目都還取得回來"
else
    test_fail "已授權的還原銷毀了讓位後才出現的後繼者 (status=$successor_status, trash=$successor_trash_count)"
fi

test_item "還原：已授權覆蓋真目錄時完成還原，舊目錄進垃圾桶且可再還原"
# 覆蓋等於刪除。使用者同意的是「換掉」，不是「銷毀」：舊目的地必須用工具自己的垃圾桶
# 機制保存，結束碼維持 0，且不得在使用者的資料夾留下暫存殘骸。
# An overwrite is a deletion. The user consented to replacing the directory, not
# to destroying it: the old destination has to be preserved through the tool's own
# trash, the exit code stays 0, and no staging debris may be left behind.
setup
cd "$TEST_WORK_DIR" || exit 1
mkdir -p authorized_dir
printf '%s\n' "TRASHED MARKER" > authorized_dir/marker.txt
"$BETTER_RM" -r authorized_dir
mkdir -p authorized_dir
printf '%s\n' "LOCAL MARKER" > authorized_dir/marker.txt
authorized_status=0
authorized_output=$("$BETTER_RM" -f --restore authorized_dir 2>&1) ||
    authorized_status=$?
authorized_staging=$(find "$TEST_WORK_DIR" -maxdepth 1 \
    -type d -name 'authorized_dir.better-rm-restore-*' -print -quit)
authorized_trashed_local=$(find "$TEST_TRASH_DIR" -type f -name marker.txt \
    -exec grep -lFx "LOCAL MARKER" {} + 2>/dev/null | head -1)
# 舊目錄必須真的能被再還原回來，而不只是「檔案還躺在垃圾桶某處」。
# The old directory must actually restore, not merely sit somewhere in the trash.
authorized_recover_status=0
rm -rf authorized_dir
"$BETTER_RM" -f --restore authorized_dir >/dev/null 2>&1 || authorized_recover_status=$?
if [ "$authorized_status" -eq 0 ] && \
   [ -z "$authorized_staging" ] && \
   [ -n "$authorized_trashed_local" ] && \
   [[ "$authorized_output" == *"--restore"* ]] && \
   [ "$authorized_recover_status" -eq 0 ] && \
   [ "$(cat authorized_dir/marker.txt 2>/dev/null)" = "LOCAL MARKER" ]; then
    test_pass "已授權真目錄還原以 0 完成，舊目錄進垃圾桶並可再度還原"
else
    test_fail "已授權真目錄還原未以 0 完成或舊目錄不可還原 (status=$authorized_status, recover=$authorized_recover_status)"
fi

test_item "還原時讓位路徑被並行行程搶佔，不得刪到別人的檔案"
# 讓位路徑一旦可預測（$dest.better-rm-restore-<PID>）且以 [ -e ] 探路後才 mv，
# 兩者之間就有空窗：並行行程在空窗內於同一路徑建目錄，mv 會把既有檔案「搬進」
# 那個目錄，成功路徑的 /bin/rm -rf 於是連同目錄裡不相干的檔案一起刪掉。
# 注入點是真正的 mv／rename 介面：讓位那一次 mv 被呼叫時才動手，重現真正的競態
# 時序；路徑由測試自行從 PID 推導，不看 better-rm 傳進來的參數，因此這個測試釘的
# 是「讓位路徑不可被外部推導與搶佔」，而不是任何內部實作細節。
# The move-aside path is predictable ($dest.better-rm-restore-<PID>) and chosen
# by an [ -e ] probe before the mv, so a concurrent process can create a
# directory there inside the window: mv then moves the existing file INTO it and
# the success path's /bin/rm -rf takes the unrelated contents with it. The
# injection happens at the real mv/rename boundary and derives the path from the
# PID rather than from better-rm's own arguments.
setup
cd "$TEST_WORK_DIR"
restore_race_bin="$TEST_WORK_DIR/restore-race-bin"
mkdir -p "$restore_race_bin"
cat > "$restore_race_bin/mv" <<'EOF'
#!/bin/sh
# 第一次 mv（讓位那一步）真正執行之前，模擬並行行程搶先在可預測路徑建目錄。
if [ ! -e "$BETTER_RM_RACE_MARKER" ]; then
    race_dir="$BETTER_RM_RACE_DEST.better-rm-restore-$PPID"
    printf '%s\n' "$race_dir" > "$BETTER_RM_RACE_MARKER"
    mkdir "$race_dir" 2>/dev/null
    printf '%s\n' "UNRELATED SENTINEL" > "$race_dir/unrelated-sentinel.txt" 2>/dev/null
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$restore_race_bin/mv"

printf '%s\n' "TRASHED CONTENT" > restore_race.txt
"$BETTER_RM" restore_race.txt
printf '%s\n' "LOCAL CONTENT" > restore_race.txt
restore_race_marker="$TEST_WORK_DIR/restore-race-marker"
restore_race_status=0
BETTER_RM_RACE_MARKER="$restore_race_marker" \
BETTER_RM_RACE_DEST="$TEST_WORK_DIR/restore_race.txt" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$restore_race_bin:$PATH" \
    "$BETTER_RM" -f --restore restore_race.txt >/dev/null 2>&1 ||
    restore_race_status=$?

restore_race_sentinel="$(find "$TEST_WORK_DIR" -maxdepth 2 -name 'unrelated-sentinel.txt' 2>/dev/null | head -1)"
if [ -s "$restore_race_marker" ] && \
   [ "$restore_race_status" -eq 0 ] && \
   [ "$(cat restore_race.txt)" = "TRASHED CONTENT" ] && \
   [ -n "$restore_race_sentinel" ] && \
   [ "$(cat "$restore_race_sentinel")" = "UNRELATED SENTINEL" ]; then
    test_pass "並行行程搶佔讓位路徑時，還原成功且不相干的檔案沒被刪掉"
else
    test_fail "還原刪掉了並行行程建立的不相干檔案 (status=$restore_race_status, sentinel='$restore_race_sentinel')"
fi

# 以下三個測試共用同一支 mv shim。它不看 better-rm 的內部命名，只看「第 N 次 mv 的
# 目的地是什麼」，再對那個路徑動手 —— 這正是並行行程枚舉父目錄後能做到的事，因此
# 釘住的是「不可刪到不是自己讓出來的物件」這個契約，而非任何實作細節。
# The three tests below share one mv shim. It never looks at better-rm's internal
# naming; it only observes the destination of the Nth mv and acts on that path,
# which is exactly what a concurrent process that enumerates the parent directory
# can do. They therefore pin the contract — never delete an object you did not set
# aside yourself — rather than any implementation detail.
make_restore_race_shim() {
    local shim_bin="$1"
    mkdir -p "$shim_bin"
    cat > "$shim_bin/mv" <<'EOF'
#!/bin/sh
n=$(cat "$BETTER_RM_RACE_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" > "$BETTER_RM_RACE_COUNT"
for a in "$@"; do dst=$a; done
if [ "$n" = "${BETTER_RM_RACE_RECORD:-}" ]; then
    printf '%s' "$dst" > "$BETTER_RM_RACE_RECORDED"
fi
if [ "$n" = "${BETTER_RM_RACE_OCCUPY:-}" ]; then
    "$BETTER_RM_REAL_MV" "$BETTER_RM_RACE_PRECIOUS" "$dst" 2>/dev/null
fi
if [ "$n" = "${BETTER_RM_RACE_SWAP:-}" ]; then
    swap_target=$(cat "$BETTER_RM_RACE_RECORDED" 2>/dev/null)
    if [ -n "$swap_target" ]; then
        "$BETTER_RM_REAL_MV" "$swap_target" "$BETTER_RM_RACE_KIDNAP" 2>/dev/null
        "$BETTER_RM_REAL_MV" "$BETTER_RM_RACE_PRECIOUS" "$swap_target" 2>/dev/null
    fi
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
    chmod +x "$shim_bin/mv"
}

count_precious_sentinels() {
    find "$TEST_WORK_DIR" -type f -name 'sentinel.txt' \
        -exec grep -lFx "PRECIOUS SENTINEL" {} + 2>/dev/null | wc -l | tr -d ' '
}

test_item "還原：暫存落點被搶佔時，垃圾桶項目與既有檔案都必須完好"
# 暫存目錄雖以 mktemp -d 獨佔建立，同 UID 的並行行程仍可枚舉父目錄找到它，並搶先
# 佔用 better-rm 即將寫入的子路徑。此時 BSD mv 會把垃圾桶項目搬「進」對方的目錄，
# 若不用 inode 驗證落點，該項目就等於從垃圾桶消失而 better-rm 毫無所覺。
# The staging directory is created exclusively with mktemp -d, but a same-UID
# process can enumerate the parent, find it and occupy the child path better-rm
# is about to write. BSD mv then moves the trashed item INTO that directory; with
# no inode check on the landing spot the item silently vanishes from the trash.
setup
cd "$TEST_WORK_DIR"
occupy_bin="$TEST_WORK_DIR/restore-occupy-bin"
make_restore_race_shim "$occupy_bin"

printf '%s\n' "TRASHED CONTENT" > occupy_target.txt
"$BETTER_RM" occupy_target.txt
printf '%s\n' "LOCAL CONTENT" > occupy_target.txt
mkdir -p precious_occupy
printf '%s\n' "PRECIOUS SENTINEL" > precious_occupy/sentinel.txt
occupy_trash_item=$(find "$TEST_TRASH_DIR" -type f -name "occupy_target.txt__*" | head -1)
occupy_status=0
BETTER_RM_RACE_COUNT="$TEST_WORK_DIR/occupy-count" \
BETTER_RM_RACE_OCCUPY=1 \
BETTER_RM_RACE_PRECIOUS="$TEST_WORK_DIR/precious_occupy" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$occupy_bin:$PATH" \
    "$BETTER_RM" -f --restore occupy_target.txt >/dev/null 2>&1 ||
    occupy_status=$?

if [ "$occupy_status" -ne 0 ] && \
   [ "$(cat occupy_target.txt)" = "LOCAL CONTENT" ] && \
   [ -n "$occupy_trash_item" ] && [ -f "$occupy_trash_item" ] && \
   [ "$(cat "$occupy_trash_item")" = "TRASHED CONTENT" ] && \
   [ "$(count_precious_sentinels)" -eq 1 ]; then
    test_pass "落點被搶佔時中止還原，垃圾桶項目、既有檔案與他人資料都完好"
else
    test_fail "落點被搶佔時吞掉了垃圾桶項目或動到既有檔案 (status=$occupy_status)"
fi

# 以下兩個測試共用同一支 stat shim：它先用真實的 device:inode 回答呼叫端，緊接著在
# 同一次呼叫裡把該 pathname 換成不相干的目錄。這模擬的是「檢查通過之後、下一個
# syscall 之前」被同 UID 行程掉包 —— shell 無法把兩者合成一個原子操作，所以真正要
# 釘住的契約是：讓位動作永遠只能是「移動」，絕不可以是遞迴刪除。
# The two tests below share one stat shim. It answers the caller with the genuine
# device:inode and then, inside the same call, swaps that pathname for an
# unrelated directory. That is exactly a same-UID swap between a passed check and
# the next syscall, which no shell can make atomic. The contract being pinned is
# therefore: clearing a destination out of the way must always be a MOVE, never a
# recursive delete.
make_dest_swap_shim() {
    local shim_bin="$1"
    mkdir -p "$shim_bin"
    cat > "$shim_bin/stat" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$BETTER_RM_SWAP_KEY" ]; then
    n=$(cat "$BETTER_RM_SWAP_COUNT" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s' "$n" > "$BETTER_RM_SWAP_COUNT"
    identity=$("$BETTER_RM_REAL_STAT" -c '%d:%i' "$last" 2>/dev/null ||
        "$BETTER_RM_REAL_STAT" -f '%d:%i' "$last" 2>/dev/null) || exit 1
    printf '%s\n' "$identity"
    if [ "$n" -eq "$BETTER_RM_SWAP_AT" ]; then
        "$BETTER_RM_REAL_MV" "$BETTER_RM_SWAP_DEST" "$BETTER_RM_SWAP_KIDNAP" || exit 1
        "$BETTER_RM_REAL_MV" "$BETTER_RM_SWAP_PRECIOUS" "$BETTER_RM_SWAP_DEST" || exit 1
    fi
    exit 0
fi
exec "$BETTER_RM_REAL_STAT" "$@"
EOF
    chmod +x "$shim_bin/stat"
}

test_item "還原：讓位前一刻目的地被掉包，必須中止且不得動到任何一方的資料"
# 目的地被證明過 inode 之後、真正讓位之前的窗口。讓位動作必須綁在那個已證明的
# inode 上：pathname 上換了東西就中止，而不是把不相干的目錄拿去讓位。
# The window between proving the destination's inode and actually clearing it.
# The clearing step must be bound to that proven inode: if the pathname now holds
# something else the restore aborts instead of displacing an unrelated directory.
setup
cd "$TEST_WORK_DIR" || exit 1
swapa_bin="$TEST_WORK_DIR/restore-swapa-bin"
make_dest_swap_shim "$swapa_bin"

mkdir -p swapa_dir
printf '%s\n' "TRASHED MARKER" > swapa_dir/marker.txt
"$BETTER_RM" -r swapa_dir
mkdir -p swapa_dir
printf '%s\n' "LOCAL MARKER" > swapa_dir/marker.txt
mkdir -p precious_swapa
printf '%s\n' "PRECIOUS SENTINEL" > precious_swapa/sentinel.txt
swapa_trash_item=$(find "$TEST_TRASH_DIR" -type d -name 'swapa_dir__*' | head -1)
swapa_status=0
BETTER_RM_SWAP_KEY="$TEST_WORK_DIR/swapa_dir" \
BETTER_RM_SWAP_AT=1 \
BETTER_RM_SWAP_COUNT="$TEST_WORK_DIR/swapa-count" \
BETTER_RM_SWAP_DEST="$TEST_WORK_DIR/swapa_dir" \
BETTER_RM_SWAP_KIDNAP="$TEST_WORK_DIR/swapa_kidnapped" \
BETTER_RM_SWAP_PRECIOUS="$TEST_WORK_DIR/precious_swapa" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$swapa_bin:$PATH" \
    "$BETTER_RM" -f --restore swapa_dir >/dev/null 2>&1 ||
    swapa_status=$?

swapa_trashed_precious=$(find "$TEST_TRASH_DIR" -type f -name sentinel.txt \
    -exec grep -lFx "PRECIOUS SENTINEL" {} + 2>/dev/null | head -1)
if [ "$swapa_status" -eq 1 ] && \
   [ -s "$TEST_WORK_DIR/swapa-count" ] && \
   [ -n "$swapa_trash_item" ] && \
   [ "$(cat "$swapa_trash_item/marker.txt" 2>/dev/null)" = "TRASHED MARKER" ] && \
   [ "$(cat swapa_kidnapped/marker.txt 2>/dev/null)" = "LOCAL MARKER" ] && \
   [ "$(count_precious_sentinels)" -eq 1 ] && \
   [ -z "$swapa_trashed_precious" ]; then
    test_pass "讓位前被掉包時中止還原，垃圾桶項目、既有目錄與他人資料都沒被動到"
else
    test_fail "讓位前被掉包時仍讓位、消耗垃圾桶項目或動到他人資料 (status=$swapa_status)"
fi

test_item "還原：讓位動作自身的最後窗口被掉包，資料只能進垃圾桶、絕不可被銷毀"
# 讓位動作內部「最後一次 stat」與「真正的 mv」之間仍是兩個 syscall，shell 無法合成
# 原子操作。因此契約不是「絕不會搬錯」，而是「搬錯也只是搬進垃圾桶」：被掉包的目錄
# 必須整份留在垃圾桶裡，任何情況下都不得被遞迴刪除。
# Inside the clearing step, the last stat and the actual mv are still two
# syscalls and no shell can fuse them. The contract is therefore not "it can
# never move the wrong object" but "moving the wrong object can only ever mean
# moving it INTO THE TRASH": the swapped directory must survive there in full.
# It must never be recursively deleted.
setup
cd "$TEST_WORK_DIR" || exit 1
swapb_bin="$TEST_WORK_DIR/restore-swapb-bin"
make_dest_swap_shim "$swapb_bin"

mkdir -p swapb_dir
printf '%s\n' "TRASHED MARKER" > swapb_dir/marker.txt
"$BETTER_RM" -r swapb_dir
mkdir -p swapb_dir
printf '%s\n' "LOCAL MARKER" > swapb_dir/marker.txt
mkdir -p precious_swapb
printf '%s\n' "PRECIOUS SENTINEL" > precious_swapb/sentinel.txt
printf '%s\n' "PRECIOUS SECOND" > precious_swapb/second.txt
swapb_status=0
swapb_output=$(BETTER_RM_SWAP_KEY="./swapb_dir" \
BETTER_RM_SWAP_AT=2 \
BETTER_RM_SWAP_COUNT="$TEST_WORK_DIR/swapb-count" \
BETTER_RM_SWAP_DEST="$TEST_WORK_DIR/swapb_dir" \
BETTER_RM_SWAP_KIDNAP="$TEST_WORK_DIR/swapb_kidnapped" \
BETTER_RM_SWAP_PRECIOUS="$TEST_WORK_DIR/precious_swapb" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$swapb_bin:$PATH" \
    "$BETTER_RM" -f --restore swapb_dir 2>&1) ||
    swapb_status=$?

swapb_sentinel=$(find "$TEST_WORK_DIR" "$TEST_TRASH_DIR" -type f -name sentinel.txt \
    -exec grep -lFx "PRECIOUS SENTINEL" {} + 2>/dev/null | head -1)
swapb_second=$(find "$TEST_WORK_DIR" "$TEST_TRASH_DIR" -type f -name second.txt \
    -exec grep -lFx "PRECIOUS SECOND" {} + 2>/dev/null | head -1)
swapb_fired=$(cat "$TEST_WORK_DIR/swapb-count" 2>/dev/null || echo 0)
if [ "$swapb_fired" -ge 2 ] && \
   [ -n "$swapb_sentinel" ] && [ -n "$swapb_second" ] && \
   [ "${swapb_sentinel#$TEST_TRASH_DIR/}" != "$swapb_sentinel" ] && \
   [ "$(cat swapb_dir/marker.txt 2>/dev/null)" = "TRASHED MARKER" ] && \
   [[ "$swapb_output" == *"--restore"* ]]; then
    test_pass "讓位窗口被掉包時對方資料整份進垃圾桶，未被刪除且訊息指出取回方式"
else
    test_fail "讓位窗口被掉包時他人資料遭銷毀或去向未被說明 (status=$swapb_status, fired=$swapb_fired)"
fi

# rename(真目錄, 非目錄) 是 ENOTDIR，Linux 的 mv -T 同樣如此。只讓「目的地是真目錄」
# 走讓位路徑，就會讓「還原目錄到既有檔案/symlink 上」整個失敗。
# rename(real dir, non-dir) is ENOTDIR, and Linux's mv -T behaves the same. Giving
# only a real-directory destination the set-aside path makes restoring a directory
# onto an existing file or symlink fail outright.
for dir_over_kind in file symlink symlink-to-dir; do
    test_item "還原：垃圾桶裡的目錄可以還原到既有的 $dir_over_kind 上"
    setup
    cd "$TEST_WORK_DIR" || exit 1
    mkdir -p over_dir
    printf '%s\n' "TRASHED MARKER" > over_dir/marker.txt
    "$BETTER_RM" -r over_dir
    case "$dir_over_kind" in
        file)
            printf '%s\n' "LOCAL FILE" > over_dir
            ;;
        symlink)
            printf '%s\n' "LINK TARGET" > over_target.txt
            ln -s over_target.txt over_dir
            ;;
        symlink-to-dir)
            mkdir -p over_target_dir
            printf '%s\n' "LINK TARGET DIR" > over_target_dir/inside.txt
            ln -s over_target_dir over_dir
            ;;
    esac
    over_status=0
    "$BETTER_RM" -f --restore over_dir >/dev/null 2>&1 || over_status=$?
    over_litter=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'over_dir.better-rm-restore-*' | wc -l | tr -d ' ')
    # 被覆蓋掉的舊目的地必須進垃圾桶，而不是被銷毀。
    # The overwritten destination must go to the trash, not be destroyed.
    if [ "$dir_over_kind" = "file" ]; then
        over_kept=$(find "$TEST_TRASH_DIR" -type f -exec grep -lFx "LOCAL FILE" {} + 2>/dev/null | head -1)
    else
        over_kept=$(find "$TEST_TRASH_DIR" -type l | head -1)
    fi
    if [ "$over_status" -eq 0 ] && \
       [ -d over_dir ] && [ ! -L over_dir ] && \
       [ "$(cat over_dir/marker.txt 2>/dev/null)" = "TRASHED MARKER" ] && \
       [ "$over_litter" -eq 0 ] && \
       [ -n "$over_kept" ]; then
        test_pass "目錄還原到既有 $dir_over_kind 上成功，舊目的地進了垃圾桶"
    else
        test_fail "目錄無法還原到既有 $dir_over_kind 上或舊目的地被銷毀 (status=$over_status)"
    fi
done

# 跨裝置時 mv 會退化成「複製後刪除」，inode 必然改變。若把「inode 相等」當成取出
# 成功的唯一條件，每一次跨裝置還原都必定失敗，而且垃圾桶來源已被消耗 —— 使用者的
# 檔案只剩暫存目錄裡那一份，日誌卻仍指向已不存在的垃圾桶路徑。
# 這裡用兩支 shim 精確重現該情境的兩個決定性性質，不需要真的掛載第二個檔案系統：
#   stat shim -> 垃圾桶子樹回報不同的 device 編號
#   mv shim   -> 來源在垃圾桶裡時改以 copy+unlink 執行（inode 因此必然改變）
# Across devices mv degrades into copy-then-unlink and the inode necessarily
# changes. Treating inode equality as the only acceptance test makes every
# cross-device restore fail after the trash source has already been consumed: the
# user's only copy is left in the staging directory while the log still points at
# a trash path that no longer exists. Two shims reproduce the two decisive
# properties without mounting a second filesystem:
#   stat shim -> the trash subtree reports a different device number
#   mv shim   -> a source inside the trash is moved by copy+unlink (new inode)
make_xdev_stat_shim() {
    local shim_bin="$1"
    mkdir -p "$shim_bin"
    cat > "$shim_bin/stat" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  "$BETTER_RM_XDEV_TRASH"/*)
    real=$("$BETTER_RM_REAL_STAT" -c '%d:%i' "$last" 2>/dev/null ||
        "$BETTER_RM_REAL_STAT" -f '%d:%i' "$last" 2>/dev/null) || exit 1
    printf '99:%s\n' "${real#*:}"
    exit 0
    ;;
esac
exec "$BETTER_RM_REAL_STAT" "$@"
EOF
    chmod +x "$shim_bin/stat"
}

test_item "還原：垃圾桶與目的地不在同一個檔案系統時仍能還原且不遺失檔案"
setup
cd "$TEST_WORK_DIR" || exit 1
xdev_bin="$TEST_WORK_DIR/restore-xdev-bin"
make_xdev_stat_shim "$xdev_bin"
cat > "$xdev_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
if [ -e "$dst" ] || [ -L "$dst" ]; then exec "$BETTER_RM_REAL_MV" "$@"; fi
cp -R "$src" "$dst" || exit 1
"$BETTER_RM_REAL_RM" -rf "$src" || exit 1
exit 0
EOF
chmod +x "$xdev_bin/mv"

printf '%s\n' "XDEV CONTENT" > xdev_target.txt
"$BETTER_RM" xdev_target.txt
xdev_trash_item=$(find "$TEST_TRASH_DIR" -type f -name 'xdev_target.txt__*' | head -1)
xdev_status=0
BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$xdev_bin:$PATH" \
    "$BETTER_RM" --restore xdev_target.txt >/dev/null 2>&1 ||
    xdev_status=$?
xdev_litter=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'xdev_target.txt.better-rm-restore-*' | wc -l | tr -d ' ')

if [ -n "$xdev_trash_item" ] && \
   [ "$xdev_status" -eq 0 ] && \
   [ -f xdev_target.txt ] && [ ! -L xdev_target.txt ] && \
   [ "$(cat xdev_target.txt)" = "XDEV CONTENT" ] && \
   [ "$xdev_litter" -eq 0 ]; then
    test_pass "跨裝置還原成功，檔案回到原處且不殘留暫存目錄"
else
    test_fail "跨裝置還原失敗或把檔案留在暫存目錄 (status=$xdev_status, litter=$xdev_litter)"
fi

test_item "還原：跨裝置中止時要把項目確實放回垃圾桶，且不得謊稱它被卡在暫存區"
# 跨裝置的復原也是一次複製，inode 必然再次改變。若復原後仍以 inode 相等驗證「有沒有
# 放回去」，就會在項目其實已經回到垃圾桶時謊報它卡在暫存區 —— 使用者會照著錯誤訊息
# 去搬一個不存在的東西。這裡在取出完成之後才讓目的地出現，強迫走中止復原路徑。
# The cross-device unwind is a copy too, so the inode changes again. Verifying the
# put-back by inode equality then reports the item as stranded in staging when it
# is actually back in the trash, sending the user after something that is not
# there. Here the destination appears only after the extraction, forcing the
# abort-and-unwind path.
setup
cd "$TEST_WORK_DIR" || exit 1
xdevunwind_bin="$TEST_WORK_DIR/restore-xdevunwind-bin"
make_xdev_stat_shim "$xdevunwind_bin"
cat > "$xdevunwind_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*)
    if [ -e "$dst" ] || [ -L "$dst" ]; then exec "$BETTER_RM_REAL_MV" "$@"; fi
    cp -R "$src" "$dst" || exit 1
    "$BETTER_RM_REAL_RM" -rf "$src" || exit 1
    # 取出完成之後，目的地才出現：未經同意的覆蓋必須中止。
    # The destination appears only after the extraction: an unauthorized
    # overwrite must abort.
    printf '%s\n' "LATE FILE" > "$BETTER_RM_XDEV_LATE_DEST"
    exit 0
    ;;
esac
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$xdevunwind_bin/mv"

printf '%s\n' "XDEV UNWIND CONTENT" > xdevunwind_target.txt
"$BETTER_RM" xdevunwind_target.txt
xdevunwind_trash_item=$(find "$TEST_TRASH_DIR" -type f -name 'xdevunwind_target.txt__*' | head -1)
xdevunwind_status=0
xdevunwind_output=$(BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_XDEV_LATE_DEST="$TEST_WORK_DIR/xdevunwind_target.txt" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$xdevunwind_bin:$PATH" \
    "$BETTER_RM" --restore xdevunwind_target.txt 2>&1) ||
    xdevunwind_status=$?
xdevunwind_staging=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'xdevunwind_target.txt.better-rm-restore-*' -print -quit)
# 沒有 shim 的第二次還原必須成功：這證明項目真的回到了日誌指向的垃圾桶路徑。
# A second restore without the shims must succeed, proving the item really is back
# at the trash path the log points to.
xdevunwind_again=0
rm -f xdevunwind_target.txt
"$BETTER_RM" --restore xdevunwind_target.txt >/dev/null 2>&1 || xdevunwind_again=$?

if [ "$xdevunwind_status" -eq 1 ] && \
   [ -n "$xdevunwind_trash_item" ] && \
   [ -z "$xdevunwind_staging" ] && \
   [[ "$xdevunwind_output" != *"暫留"* ]] && \
   [ "$xdevunwind_again" -eq 0 ] && \
   [ "$(cat xdevunwind_target.txt 2>/dev/null)" = "XDEV UNWIND CONTENT" ]; then
    test_pass "跨裝置中止把項目放回垃圾桶、沒有謊稱卡在暫存區，之後仍可正常還原"
else
    test_fail "跨裝置中止遺失項目或謊報其位置 (status=$xdevunwind_status, again=$xdevunwind_again)"
fi

test_item "還原：跨裝置取出失敗時，錯誤訊息必須指出資料實際在哪裡"
# exit 1 的契約是「錯誤訊息會指名任何無法放回原位的東西」。跨裝置複製可能在來源已被
# 消耗之後才失敗，此時沉默地回傳 1 會讓使用者以為檔案還在垃圾桶，而下一次 --restore
# 只會說「找不到」。
# The exit-1 contract is that the error names anything that could not be put back.
# A cross-device copy can fail after the source has already been consumed, and
# returning 1 silently would leave the user believing the file is still in the
# trash while the next --restore only reports "not found".
setup
cd "$TEST_WORK_DIR" || exit 1
xdevfail_bin="$TEST_WORK_DIR/restore-xdevfail-bin"
make_xdev_stat_shim "$xdevfail_bin"
# 複製完成、來源也已刪除，但 mv 最後仍回報失敗（例如複製後的收尾出錯）。
# The copy completed and the source is already gone, but mv still reports failure
# (the way a cross-device move can fail during its final steps).
cat > "$xdevfail_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
if [ -e "$dst" ] || [ -L "$dst" ]; then exec "$BETTER_RM_REAL_MV" "$@"; fi
cp -R "$src" "$dst" || exit 1
"$BETTER_RM_REAL_RM" -rf "$src" || exit 1
exit 1
EOF
chmod +x "$xdevfail_bin/mv"

printf '%s\n' "XDEV FAIL CONTENT" > xdevfail_target.txt
"$BETTER_RM" xdevfail_target.txt
xdevfail_status=0
xdevfail_output=$(BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$xdevfail_bin:$PATH" \
    "$BETTER_RM" --restore xdevfail_target.txt 2>&1) ||
    xdevfail_status=$?
xdevfail_survivor=$(find "$TEST_WORK_DIR" -type f \
    -exec grep -lFx "XDEV FAIL CONTENT" {} + 2>/dev/null | head -1)

if [ "$xdevfail_status" -eq 1 ] && \
   [ -n "$xdevfail_survivor" ] && \
   [[ "$xdevfail_output" == *"$xdevfail_survivor"* ]]; then
    test_pass "跨裝置取出失敗時資料仍在，且訊息直接指出它的實際路徑"
else
    test_fail "跨裝置取出失敗時資料遺失或訊息沒有指出位置 (status=$xdevfail_status, survivor='$xdevfail_survivor')"
fi

test_item "還原：垃圾桶磁碟裝不下舊目的地時，不得開始那次跨裝置複製"
# 迴歸（在真實的 20MB HFS+ 卷宗上重現過）：垃圾桶在另一顆磁碟、舊目的地又大過它的
# 剩餘空間時，「讓位＝移入垃圾桶」會退化成一次完整複製並在 ENOSPC 半途死掉：垃圾桶
# 磁碟被一份沒人提起的半成品複本永久佔滿、使用者的檔案停在暫存目錄裡沒有還原、日誌
# 指向的垃圾桶來源也已經被消耗。同裝置不受影響（rename 不需要空間）。
# 這裡用兩支 shim 精確重現決定性的兩個性質：垃圾桶在別的 device，且它的可用空間
# 小於舊目的地。正確行為是「先量再決定」——量到裝不下就不要開始複製，改用同裝置的
# rename 把舊目的地移到旁邊，還原照樣完成，兩份資料都在。
# Regression, reproduced on a real 20MB HFS+ volume: with the trash on another
# device and the old destination larger than its free space, clearing the way by
# moving into the trash degrades into a full copy that dies of ENOSPC half way —
# the trash volume ends up permanently filled with a half-copy nothing mentions,
# the user's file is never restored, and the trash source the log points at has
# already been consumed. Same-device is unaffected: a rename needs no space.
# Two shims reproduce the decisive properties: the trash is on another device and
# reports less free space than the destination. The correct behaviour is to
# measure first and never start that copy, setting the old destination aside with
# a same-device rename instead, so the restore still completes with both objects
# intact.
setup
cd "$TEST_WORK_DIR" || exit 1
nospace_bin="$TEST_WORK_DIR/restore-nospace-bin"
make_xdev_stat_shim "$nospace_bin"
cat > "$nospace_bin/df" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  "$BETTER_RM_XDEV_TRASH"*)
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted-on\n'
    printf 'shimfs 1024 1023 1 100%% %s\n' "$last"
    exit 0
    ;;
esac
exec "$BETTER_RM_REAL_DF" "$@"
EOF
chmod +x "$nospace_bin/df"

printf '%s\n' "NOSPACE ORIGINAL" > nospace.txt
"$BETTER_RM" nospace.txt
# 舊目的地必須大到 du 量得出來（否則量到 0 就談不上「裝不下」）
# The destination must be large enough for du to see it; a 0 KB destination
# cannot be "too big" for anything.
mkdir -p nospace.txt
dd if=/dev/zero of=nospace.txt/payload.bin bs=1024 count=64 >/dev/null 2>&1
printf '%s\n' "NOSPACE DESTINATION" > nospace.txt/keep.txt
nospace_status=0
nospace_output=$(BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_DF="$(command -v df)" \
PATH="$nospace_bin:$PATH" \
    "$BETTER_RM" -f --restore nospace.txt 2>&1) || nospace_status=$?
nospace_aside=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'nospace.txt.better-rm-displaced-*' -print -quit)
nospace_trashed=$(find "$TEST_TRASH_DIR" -name 'nospace.txt__*' 2>/dev/null | wc -l | tr -d ' ')

# 就地讓位是降級結果，結束碼是 2 而不是 0（見下面「降級結果」那一項）。
# The in-place set-aside is a degraded outcome and exits 2, not 0 (see the
# "degraded outcome" item below).
if [ "$nospace_status" -eq 2 ] && \
   [ -f nospace.txt ] && [ ! -L nospace.txt ] && \
   [ "$(cat nospace.txt)" = "NOSPACE ORIGINAL" ] && \
   [ -n "$nospace_aside" ] && \
   [ -f "$nospace_aside/nospace.txt/keep.txt" ] && \
   grep -qFx "NOSPACE DESTINATION" "$nospace_aside/nospace.txt/keep.txt" && \
   [ "$nospace_trashed" -eq 0 ] && \
   [[ "$nospace_output" == *"$nospace_aside"* ]]; then
    test_pass "垃圾桶磁碟裝不下時改用同裝置 rename 讓位，還原完成且舊目的地完好並被指名"
else
    test_fail "垃圾桶磁碟裝不下時仍走複製、遺失舊目的地或沒說它去了哪裡 (status=$nospace_status, aside='$nospace_aside', trashed=$nospace_trashed)"
fi

test_item "還原：讓位到垃圾桶失敗但舊目的地完好時，改用就地讓位而不是整個中止"
# 空間是在量完之後才不夠、垃圾桶暫時寫不進去⋯⋯「移入垃圾桶」還是可能失敗。此時舊
# 目的地若確實還是那個已驗證的物件，就沒有理由讓使用者同意過的覆蓋整個失敗：改用
# 同裝置 rename 讓位即可，舊目的地一樣不會被銷毀。身分不符則必須中止（另有測試）。
# The trash route can still fail after the measurement — space ran out, the trash
# is momentarily unwritable. When the old destination really is still the object
# that was verified there is no reason to fail the overwrite the user consented
# to: set it aside with a same-device rename instead, still destroying nothing.
# A mismatching identity must abort, which a separate test covers.
setup
cd "$TEST_WORK_DIR" || exit 1
trashfail_bin="$TEST_WORK_DIR/restore-trashfail-bin"
mkdir -p "$trashfail_bin"
cat > "$trashfail_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
# 只讓「把東西搬進垃圾桶」這一次失敗；從垃圾桶取出不受影響。
# Fail only the move INTO the trash; taking things out of it is unaffected.
case "$dst" in
  "$BETTER_RM_TRASHFAIL_TRASH"/*)
    case "$src" in
      "$BETTER_RM_TRASHFAIL_TRASH"/*) exec "$BETTER_RM_REAL_MV" "$@" ;;
      *) exit 1 ;;
    esac
    ;;
esac
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$trashfail_bin/mv"

printf '%s\n' "TRASHFAIL ORIGINAL" > trashfail.txt
"$BETTER_RM" trashfail.txt
mkdir -p trashfail.txt
printf '%s\n' "TRASHFAIL DESTINATION" > trashfail.txt/keep.txt
trashfail_status=0
trashfail_output=$(BETTER_RM_TRASHFAIL_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$trashfail_bin:$PATH" \
    "$BETTER_RM" -f --restore trashfail.txt 2>&1) || trashfail_status=$?
trashfail_aside=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'trashfail.txt.better-rm-displaced-*' -print -quit)

# 就地讓位是降級結果，結束碼是 2 而不是 0（見下面「降級結果」那一項）。
# The in-place set-aside is a degraded outcome and exits 2, not 0 (see the
# "degraded outcome" item below).
if [ "$trashfail_status" -eq 2 ] && \
   [ -f trashfail.txt ] && [ ! -L trashfail.txt ] && \
   [ "$(cat trashfail.txt)" = "TRASHFAIL ORIGINAL" ] && \
   [ -n "$trashfail_aside" ] && \
   grep -qFx "TRASHFAIL DESTINATION" "$trashfail_aside/trashfail.txt/keep.txt" 2>/dev/null && \
   [[ "$trashfail_output" == *"$trashfail_aside"* ]]; then
    test_pass "讓位到垃圾桶失敗時改用就地讓位，還原完成且舊目的地完好並被指名"
else
    test_fail "讓位到垃圾桶失敗時整個中止或遺失舊目的地 (status=$trashfail_status, aside='$trashfail_aside')"
fi

test_item "還原：讓位進了垃圾桶但日誌沒寫成功時，不得叫使用者去跑一個註定失敗的 --restore"
# 讓位成功、deletion log 卻寫不進去，是可以判定的狀態（前一行已經印出「無法寫入刪除
# 日誌」）。此時照抄成功版本的話術，會叫使用者去跑 `rm --restore '<名字>'`，而那一定
# 回「找不到刪除記錄」——東西真的在垃圾桶裡，指示卻是假的。
# A set-aside that succeeded while the deletion log did not is a decidable state:
# the preceding line already said the log could not be written. Reusing the
# success wording then tells the user to run `rm --restore '<name>'`, which is
# guaranteed to answer "no deletion record found" — the data really is in the
# trash but the instruction is false.
setup
cd "$TEST_WORK_DIR" || exit 1
printf '%s\n' "UNLOGGED ORIGINAL" > unlogged.txt
"$BETTER_RM" unlogged.txt
# 把紀錄搬到舊版垃圾桶日誌，再把主日誌的路徑換成一個目錄：還原仍找得到紀錄，但讓位
# 這一步寫不進任何日誌。
# Move the record to the legacy trash log and replace the primary log path with a
# directory: the restore still finds its record while the set-aside cannot log.
grep -v '^#' "$TEST_STATE_DIR/deletion.log" > "$TEST_TRASH_DIR/.deletion_log"
rm -f "$TEST_STATE_DIR/deletion.log"
mkdir -p "$TEST_STATE_DIR/deletion.log"
mkdir -p unlogged.txt
printf '%s\n' "UNLOGGED DESTINATION" > unlogged.txt/keep.txt
unlogged_status=0
unlogged_output=$("$BETTER_RM" -f --restore unlogged.txt 2>&1) || unlogged_status=$?
unlogged_trashed=$(find "$TEST_TRASH_DIR" -type f -name 'keep.txt' 2>/dev/null | head -1)
unlogged_again=0
rm -f unlogged.txt
"$BETTER_RM" -f --restore unlogged.txt >/dev/null 2>&1 || unlogged_again=$?

if [ "$unlogged_status" -eq 0 ] && \
   [ -n "$unlogged_trashed" ] && \
   grep -qFx "UNLOGGED DESTINATION" "$unlogged_trashed" && \
   [[ "$unlogged_output" == *"刪除日誌沒寫成功"* ]] && \
   [[ "$unlogged_output" != *"可用 rm --restore"* ]] && \
   [ "$unlogged_again" -ne 0 ]; then
    test_pass "日誌沒寫成功時說出實情，沒有給出那句註定失敗的 --restore 指示"
else
    test_fail "日誌沒寫成功時仍宣稱可用 --restore 取回或漏講 (status=$unlogged_status, again=$unlogged_again)"
fi

test_item "還原：跨裝置時暫存落點被目錄佔走、項目被搬了進去，不得當成取出成功"
# 跨裝置沒有 inode 可比，驗收只剩三個條件。少了「落點不是那個吞了項目的目錄」這一
# 條，攻擊者先建好的目錄就會被當成取出結果：它會被 publish 到使用者的路徑上、使用者
# 的檔案埋在裡面，而舊目的地還被送進垃圾桶，全程 exit 0。
# 少了復原時的「$buried 真的是我們的項目（或跨裝置無從比對）」判斷，則是項目撈不
# 回垃圾桶，日誌指向一個已經不存在的來源。
# Across devices there is no inode to compare and the acceptance test is down to
# three conditions. Without "the landing spot is not the directory that swallowed
# the item", a directory a concurrent process created first is taken for the
# extraction result: it gets published to the user's path with the user's file
# buried inside it, the old destination goes to the trash, and the whole thing
# exits 0. Without the recovery check that $buried really is our item, the item
# never gets pulled back to the trash and the log points at a source that is gone.
setup
cd "$TEST_WORK_DIR" || exit 1
buried_bin="$TEST_WORK_DIR/restore-buried-bin"
make_xdev_stat_shim "$buried_bin"
cat > "$buried_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
if [ -e "$dst" ] || [ -L "$dst" ]; then exec "$BETTER_RM_REAL_MV" "$@"; fi
# 並行行程搶先在暫存落點建好自己的目錄，跨裝置的 mv 於是把項目複製「進去」。
# A concurrent process created its own directory at the staging landing first, so
# the cross-device mv copies the item INTO it.
mkdir -p "$dst" || exit 1
printf '%s\n' "BURIED ATTACKER" > "$dst/attacker-marker"
cp -R "$src" "$dst/" || exit 1
"$BETTER_RM_REAL_RM" -rf "$src" || exit 1
exit 0
EOF
chmod +x "$buried_bin/mv"

printf '%s\n' "BURIED ORIGINAL" > buried.txt
"$BETTER_RM" buried.txt
printf '%s\n' "BURIED LOCAL" > buried.txt
buried_status=0
BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$buried_bin:$PATH" \
    "$BETTER_RM" -f --restore buried.txt >/dev/null 2>&1 || buried_status=$?
buried_attacker=$(find "$TEST_WORK_DIR" -type f -name 'attacker-marker' -print -quit)
# 沒有 shim 的第二次還原必須成功：這證明項目真的被撈回了日誌指向的垃圾桶路徑。
# A second restore without the shims must succeed, proving the item really was
# pulled back to the trash path the log points at.
buried_again=0
rm -rf buried.txt
"$BETTER_RM" --restore buried.txt >/dev/null 2>&1 || buried_again=$?

if [ "$buried_status" -eq 1 ] && \
   [ -n "$buried_attacker" ] && \
   [ "$buried_again" -eq 0 ] && \
   [ -f buried.txt ] && [ ! -L buried.txt ] && \
   [ "$(cat buried.txt)" = "BURIED ORIGINAL" ]; then
    test_pass "被吞進佔位目錄的取出不算成功，項目回到垃圾桶且之後仍可正常還原"
else
    test_fail "把佔位目錄當成取出結果或沒把項目放回垃圾桶 (status=$buried_status, again=$buried_again)"
fi

test_item "還原：暫存落點先被別人建成檔案時，既不得採用它也不得覆蓋它"
# BSD 的 mv -n 在落點已存在時「靜默不做事並回傳 0」。少了「垃圾桶來源確實已消失」
# 這一條，那個先到的檔案就會被當成取出結果 publish 到使用者的路徑上（exit 0，內容
# 是別人的）；把取出的 -n 換成 -f，則變成 better-rm 主動銷毀那個不屬於它的檔案。
# BSD's mv -n does nothing and returns 0 when the landing spot exists. Without
# "the trash source really is gone", the file that got there first is taken for
# the extraction result and published to the user's path (exit 0, someone else's
# content); switching the extraction's -n to -f instead makes better-rm destroy a
# file it did not create.
setup
cd "$TEST_WORK_DIR" || exit 1
occupied_bin="$TEST_WORK_DIR/restore-occupied-bin"
make_xdev_stat_shim "$occupied_bin"
cat > "$occupied_bin/mv" <<'EOF'
#!/bin/sh
policy="$1"
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
if [ ! -e "$BETTER_RM_OCCUPIED_FLAG" ]; then
    : > "$BETTER_RM_OCCUPIED_FLAG"
    printf '%s\n' "OCCUPIED ATTACKER" > "$dst"
fi
if { [ -e "$dst" ] || [ -L "$dst" ]; } && [ "$policy" = "-n" ]; then
    exit 0
fi
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$occupied_bin/mv"

printf '%s\n' "OCCUPIED ORIGINAL" > occupied.txt
"$BETTER_RM" occupied.txt
printf '%s\n' "OCCUPIED LOCAL" > occupied.txt
occupied_status=0
BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_OCCUPIED_FLAG="$TEST_WORK_DIR/occupied-injected" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$occupied_bin:$PATH" \
    "$BETTER_RM" -f --restore occupied.txt >/dev/null 2>&1 || occupied_status=$?
occupied_attacker=$(find "$TEST_WORK_DIR" -type f \
    -exec grep -lFx "OCCUPIED ATTACKER" {} + 2>/dev/null | head -1)
occupied_again=0
rm -f occupied.txt
"$BETTER_RM" --restore occupied.txt >/dev/null 2>&1 || occupied_again=$?

if [ "$occupied_status" -eq 1 ] && \
   [ -n "$occupied_attacker" ] && \
   [ "$occupied_again" -eq 0 ] && \
   [ "$(cat occupied.txt)" = "OCCUPIED ORIGINAL" ]; then
    test_pass "先佔走落點的檔案既沒被採用也沒被銷毀，垃圾桶項目之後仍可正常還原"
else
    test_fail "採用了別人的檔案或把它銷毀了 (status=$occupied_status, attacker='$occupied_attacker', again=$occupied_again)"
fi

test_item "還原：暫存落點根本沒有東西時不算取出成功，既有目的地必須留在原地"
# 跨裝置的 mv 可能回報成功、消耗了來源，落點卻什麼也沒有（例如網路檔案系統中途失
# 效）。少了「落點至少有個身分」這一條，空無一物會被當成取出成功：既有目的地被清進
# 垃圾桶讓位，然後才發現沒有東西可以就位。使用者什麼也沒得到，卻少了原本的目的地。
# A cross-device mv can report success and consume the source while leaving
# nothing at the landing spot (a network filesystem dropping out mid-copy).
# Without "the landing spot has an identity at all", nothing is taken for a
# successful extraction: the existing destination is cleared into the trash to
# make room and only then does the publish find there is nothing to put in place.
# The user gains nothing and loses the destination they had.
setup
cd "$TEST_WORK_DIR" || exit 1
vanish_bin="$TEST_WORK_DIR/restore-vanish-bin"
make_xdev_stat_shim "$vanish_bin"
cat > "$vanish_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
"$BETTER_RM_REAL_RM" -rf "$src" || exit 1
exit 0
EOF
chmod +x "$vanish_bin/mv"

printf '%s\n' "VANISH ORIGINAL" > vanish.txt
"$BETTER_RM" vanish.txt
mkdir -p vanish.txt
printf '%s\n' "VANISH DESTINATION" > vanish.txt/keep.txt
vanish_status=0
BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$vanish_bin:$PATH" \
    "$BETTER_RM" -f --restore vanish.txt >/dev/null 2>&1 || vanish_status=$?

if [ "$vanish_status" -ne 0 ] && \
   [ -d vanish.txt ] && [ ! -L vanish.txt ] && \
   grep -qFx "VANISH DESTINATION" vanish.txt/keep.txt 2>/dev/null; then
    test_pass "落點沒有身分就不算取出成功，既有目的地原封不動"
else
    test_fail "把空無一物當成取出成功並清掉了既有目的地 (status=$vanish_status)"
fi

test_item "還原：同一裝置的取出必須以 inode 驗收，落點被掉包就不算成功"
# 同一裝置的 mv 就是 rename，inode 必然保留，所以 inode 相等是可用的證明——這也是
# 為什麼「是否跨裝置」必須真的判斷，而不是一律套用跨裝置那組較鬆的條件。若同裝置也
# 走鬆的那條，攻擊者只要在 mv 與 stat 之間把落點換成自己的檔案，就會被當成取出結果
# publish 到使用者的路徑上。
# Within one device mv is a rename and the inode is necessarily preserved, so
# inode equality is a usable proof — which is why "is this cross-device" has to be
# determined rather than assumed. If the same device took the looser branch, an
# attacker swapping the landing spot between the mv and the stat would have its
# own file published as the restore result.
setup
cd "$TEST_WORK_DIR" || exit 1
swap_bin="$TEST_WORK_DIR/restore-swap-bin"
mkdir -p "$swap_bin"
cat > "$swap_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_SWAP_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
"$BETTER_RM_REAL_MV" "$@" || exit $?
# mv 已經完成、better-rm 還沒 stat：落點在這個窗口被換成攻擊者的檔案。
# The mv is done and better-rm has not stat'd yet: the landing spot is swapped
# for the attacker's file inside that window.
"$BETTER_RM_REAL_MV" "$dst" "$BETTER_RM_SWAP_STASH" || exit 1
printf '%s\n' "SWAP ATTACKER" > "$dst"
exit 0
EOF
chmod +x "$swap_bin/mv"

printf '%s\n' "SWAP ORIGINAL" > swap.txt
"$BETTER_RM" swap.txt
printf '%s\n' "SWAP LOCAL" > swap.txt
swap_status=0
BETTER_RM_SWAP_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_SWAP_STASH="$TEST_WORK_DIR/swap-stash.txt" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$swap_bin:$PATH" \
    "$BETTER_RM" -f --restore swap.txt >/dev/null 2>&1 || swap_status=$?

if [ "$swap_status" -ne 0 ] && \
   [ -f swap.txt ] && [ ! -L swap.txt ] && \
   [ "$(cat swap.txt)" = "SWAP LOCAL" ] && \
   ! grep -qFx "SWAP ATTACKER" swap.txt 2>/dev/null; then
    test_pass "同裝置落點被掉包時中止，既有檔案未被攻擊者的內容取代"
else
    test_fail "同裝置走了鬆的驗收，攻擊者的檔案被當成還原結果 (status=$swap_status)"
fi

test_item "還原：跨裝置復原時 mv 回報成功但東西沒回垃圾桶，必須說出它還在暫存區"
# 跨裝置的復原是一次複製，無法用 inode 驗證，只能檢查「垃圾桶路徑真的又有東西了」。
# 少了這個檢查，一次「回傳 0 卻什麼也沒做」的 mv 會讓 better-rm 相信項目已經回到垃圾
# 桶而閉口不談——使用者的資料其實還在暫存目錄裡，而下一次 --restore 只會說找不到。
# 這與既有的「不得謊稱卡在暫存區」是一體兩面：兩個方向都不能亂講。
# The cross-device unwind is a copy and cannot be verified by inode; all that can
# be checked is that something really is back at the trash path. Without that
# check, an mv that returns 0 without doing anything convinces better-rm the item
# is back in the trash and it says nothing — while the user's data is still in the
# staging directory and the next --restore only reports "not found". This is the
# mirror image of the existing "must not claim it is stranded" test: neither
# direction may be misreported.
setup
cd "$TEST_WORK_DIR" || exit 1
nounwind_bin="$TEST_WORK_DIR/restore-nounwind-bin"
make_xdev_stat_shim "$nounwind_bin"
cat > "$nounwind_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
# 放回垃圾桶的那一次：回傳成功，但什麼也不做。
# The put-back into the trash: report success, do nothing.
case "$dst" in
  "$BETTER_RM_XDEV_TRASH"/*)
    case "$src" in
      "$BETTER_RM_XDEV_TRASH"/*) ;;
      *) exit 0 ;;
    esac
    ;;
esac
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
if [ -e "$dst" ] || [ -L "$dst" ]; then exec "$BETTER_RM_REAL_MV" "$@"; fi
cp -R "$src" "$dst" || exit 1
"$BETTER_RM_REAL_RM" -rf "$src" || exit 1
# 取出完成之後目的地才出現：未經同意的覆蓋必須中止，於是走到復原路徑。
# The destination appears only after the extraction, so the unauthorized
# overwrite aborts and the unwind runs.
printf '%s\n' "NOUNWIND LATE" > "$BETTER_RM_NOUNWIND_LATE"
exit 0
EOF
chmod +x "$nounwind_bin/mv"

printf '%s\n' "NOUNWIND ORIGINAL" > nounwind.txt
"$BETTER_RM" nounwind.txt
nounwind_status=0
nounwind_output=$(BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_NOUNWIND_LATE="$TEST_WORK_DIR/nounwind.txt" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$nounwind_bin:$PATH" \
    "$BETTER_RM" --restore nounwind.txt 2>&1) || nounwind_status=$?
nounwind_survivor=$(find "$TEST_WORK_DIR" -type f \
    -exec grep -lFx "NOUNWIND ORIGINAL" {} + 2>/dev/null | head -1)

if [ "$nounwind_status" -eq 1 ] && \
   [ -n "$nounwind_survivor" ] && \
   [[ "$nounwind_output" == *"暫留"* ]] && \
   [[ "$nounwind_output" == *"$nounwind_survivor"* ]]; then
    test_pass "沒真的放回垃圾桶時說出項目還在暫存區，並指名它的路徑"
else
    test_fail "誤信項目已回垃圾桶而閉口不談 (status=$nounwind_status, survivor='$nounwind_survivor')"
fi

test_item "還原：取出失敗時，只有確定是自己的項目才可以放回垃圾桶"
# 取出失敗後會嘗試把「被搬進佔位目錄的項目」撈回垃圾桶。同一裝置有 inode 可比，就
# 必須比：少了這個判斷，撈回去的可能是別人放在那裡的東西，於是垃圾桶路徑與日誌紀錄
# 從此指向攻擊者的內容，下一次 --restore 會把它當成使用者的檔案還原出來。
# After a failed extraction the item that was moved into an occupying directory is
# pulled back to the trash. Within one device there is an inode to compare, so it
# must be compared: without that check whatever another process left there gets
# pulled in instead, the trash path and its log record then point at the
# attacker's content, and the next --restore hands it to the user as their file.
setup
cd "$TEST_WORK_DIR" || exit 1
recover_bin="$TEST_WORK_DIR/restore-recover-bin"
mkdir -p "$recover_bin"
cat > "$recover_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_RECOVER_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
# 並行行程佔走了暫存落點，而且在裡面放了一個和垃圾桶項目同名、卻不是它的東西。
# A concurrent process took the staging landing and put something of its own
# there under the trashed item's name.
"$BETTER_RM_REAL_MV" "$src" "$BETTER_RM_RECOVER_STASH" || exit 1
mkdir -p "$dst" || exit 1
printf '%s\n' "RECOVER ATTACKER" > "$dst/$(basename "$src")"
exit 0
EOF
chmod +x "$recover_bin/mv"

printf '%s\n' "RECOVER ORIGINAL" > recover.txt
"$BETTER_RM" recover.txt
recover_status=0
BETTER_RM_RECOVER_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_RECOVER_STASH="$TEST_WORK_DIR/recover-stash.bin" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$recover_bin:$PATH" \
    "$BETTER_RM" --restore recover.txt >/dev/null 2>&1 || recover_status=$?
# 沒有 shim 的第二次還原：垃圾桶路徑上若被塞進攻擊者的內容，這裡就會把它當成使用者
# 的檔案還原出來。
# A second restore without the shims: anything pushed onto the trash path would be
# handed back here as the user's file.
"$BETTER_RM" --restore recover.txt >/dev/null 2>&1

if [ "$recover_status" -eq 1 ] && \
   ! grep -qFx "RECOVER ATTACKER" recover.txt 2>/dev/null && \
   grep -qFx "RECOVER ORIGINAL" "$TEST_WORK_DIR/recover-stash.bin"; then
    test_pass "身分不符的東西沒有被放回垃圾桶，之後的還原也拿不到攻擊者的內容"
else
    test_fail "把別人的東西放回垃圾桶並當成使用者的檔案還原 (status=$recover_status)"
fi

test_item "還原：受保護的目的地不得因為垃圾桶裝不下就繞過保護、被移到旁邊讓位"
# 就地讓位是為了「垃圾桶磁碟裝不下」而存在的退路，不是繞過保護的後門。move_to_trash
# 拒絕受保護路徑是原則問題，不是空間問題；若空間不足就改用就地讓位，等於自己把
# .git 這類保護拆掉——東西雖然沒被銷毀，但保護的目的地照樣被搬走了。
# The in-place route exists for "the trash volume cannot hold it", not as a way
# around the protected-path rule. move_to_trash refuses those on principle rather
# than for lack of space, so routing around the refusal when space runs short
# dismantles the .git protection: nothing is destroyed, but the protected
# destination is moved out of the way all the same.
setup
cd "$TEST_WORK_DIR" || exit 1
protected_bin="$TEST_WORK_DIR/restore-protected-bin"
make_xdev_stat_shim "$protected_bin"
cat > "$protected_bin/df" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  "$BETTER_RM_XDEV_TRASH"*)
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted-on\n'
    printf 'shimfs 1024 1023 1 100%% %s\n' "$last"
    exit 0
    ;;
esac
exec "$BETTER_RM_REAL_DF" "$@"
EOF
chmod +x "$protected_bin/df"

# better-rm 自己不會把 .git 移入垃圾桶（那正是保護的用意），所以紀錄與垃圾桶項目
# 直接造出來，才能測到「還原一個受保護名稱到既有的同名目錄上」。
# better-rm will not trash a .git itself — that is the protection — so the record
# and the trashed item are fabricated to reach "restore a protected name over an
# existing directory of the same name".
mkdir -p "$TEST_TRASH_DIR$TEST_WORK_DIR"
protected_trash="$TEST_TRASH_DIR$TEST_WORK_DIR/.git__20260101_000000_000000000__nohash"
printf '%s\n' "PROTECTED ORIGINAL" > "$protected_trash"
mkdir -p "$TEST_STATE_DIR"
{
    printf '%s\n' "# Better-RM Deletion Log"
    printf '%s | %s | %s | %s | %s\n' \
        "20260101_000000_000000000" \
        "$TEST_WORK_DIR/.git" \
        "$protected_trash" \
        "nohash" \
        "file"
} > "$TEST_STATE_DIR/deletion.log"
mkdir -p .git
dd if=/dev/zero of=.git/payload.bin bs=1024 count=64 >/dev/null 2>&1
printf '%s\n' "PROTECTED DESTINATION" > .git/keep.txt
protected_status=0
BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_DF="$(command -v df)" \
PATH="$protected_bin:$PATH" \
    "$BETTER_RM" -f --restore .git >/dev/null 2>&1 || protected_status=$?
protected_aside=$(find "$TEST_WORK_DIR" -maxdepth 1 -name '.git.better-rm-displaced-*' -print -quit)

if [ "$protected_status" -ne 0 ] && \
   [ -d .git ] && [ ! -L .git ] && \
   grep -qFx "PROTECTED DESTINATION" .git/keep.txt 2>/dev/null && \
   [ -z "$protected_aside" ] && \
   [ -f "$protected_trash" ]; then
    test_pass "受保護的目的地沒有被就地讓位，垃圾桶項目也回到原處"
else
    test_fail "空間不足時繞過了保護、把受保護的目的地搬走 (status=$protected_status, aside='$protected_aside')"
fi

# 覆蓋等於刪除，而這個工具的全部前提是「刪除一定救得回來」。先前只有 rename 換不掉的
# 目的地（兩種真目錄形狀）會被移進垃圾桶讓位，其餘一律由核心在 rename 當下解除連結：
# 實測 `rm -f --restore -- <檔案>` exit 0、沒有任何提示、垃圾桶項目 1 → 0，而原本佔著
# 目的地的那個物件在垃圾桶與工作目錄都不存在，沒有任何取回的方法。
# 這一組把每一種佔位物件都跑一遍，並且逐一驗證它真的能「用自己的名字再被還原回來」
# ——那需要一筆真的 deletion log 紀錄，不是「垃圾桶底下找得到某個檔案」而已。
# An overwrite is a deletion, and this tool's whole premise is that a deletion can
# be undone. Only a destination rename could not replace (the two real-directory
# shapes) used to be moved into the trash; every other one was unlinked by the
# kernel as part of the rename. Measured: `rm -f --restore -- <file>` exited 0 with
# no prompt, took the trash from one entry to zero, and left the object that had
# been occupying the destination in neither the trash nor the working directory,
# with no recovery path at all.
# Every occupant kind below is checked for coming back under its own name with a
# second --restore, which needs a real deletion-log record rather than merely
# "something exists under the trash root".
for occupant_kind in file symlink symlink-to-dir hardlink empty-dir non-empty-dir; do
    test_item "還原：既有的 $occupant_kind 佔著目的地時要進垃圾桶，且之後仍還原得回來"
    setup
    cd "$TEST_WORK_DIR" || exit 1
    printf '%s\n' "RESTORED CONTENT" > occupant.txt
    "$BETTER_RM" occupant.txt
    case "$occupant_kind" in
        file)
            printf '%s\n' "OCCUPANT CONTENT" > occupant.txt
            ;;
        symlink)
            printf '%s\n' "BYSTANDER CONTENT" > occupant_link_target.txt
            ln -s occupant_link_target.txt occupant.txt
            ;;
        symlink-to-dir)
            mkdir -p occupant_link_dir
            printf '%s\n' "BYSTANDER CONTENT" > occupant_link_dir/inside.txt
            ln -s occupant_link_dir occupant.txt
            ;;
        hardlink)
            printf '%s\n' "OCCUPANT CONTENT" > occupant_peer.txt
            ln occupant_peer.txt occupant.txt
            ;;
        empty-dir)
            mkdir -p occupant.txt
            ;;
        non-empty-dir)
            mkdir -p occupant.txt
            printf '%s\n' "OCCUPANT CONTENT" > occupant.txt/keep.txt
            ;;
    esac
    occupant_status=0
    occupant_output=$("$BETTER_RM" -f --restore -- occupant.txt 2>&1) || occupant_status=$?
    occupant_trashed=$(find "$TEST_TRASH_DIR" -maxdepth 6 -name 'occupant.txt__*' 2>/dev/null | wc -l | tr -d ' ')
    occupant_litter=$(find "$TEST_WORK_DIR" -maxdepth 1 \
        -name 'occupant.txt.better-rm-*' 2>/dev/null | wc -l | tr -d ' ')
    # 讓位的物件必須以自己的名字回得來：把還原出來的檔案挪開，再還原一次。
    # The displaced occupant must come back under its own name: move the restored
    # item aside and restore once more.
    occupant_back_status=0
    mv occupant.txt occupant_restored_away.txt 2>/dev/null
    "$BETTER_RM" --restore -- occupant.txt >/dev/null 2>&1 || occupant_back_status=$?

    occupant_ok=1
    if [ "$occupant_status" -ne 0 ] || [ "$occupant_back_status" -ne 0 ]; then
        occupant_ok=0
    fi
    if [ "$(cat occupant_restored_away.txt 2>/dev/null)" != "RESTORED CONTENT" ]; then
        occupant_ok=0
    fi
    # 讓位一律走垃圾桶：既不是銷毀（0 筆），也不是就地讓位（那會留下 displaced 目錄）。
    # The occupant goes to the trash: neither destroyed (zero entries) nor set
    # aside in place, which would leave a displaced directory behind.
    if [ "$occupant_trashed" -ne 1 ] || [ "$occupant_litter" -ne 0 ]; then
        occupant_ok=0
    fi
    # 使用者同意的是覆蓋，不是銷毀：舊目的地去了哪裡必須主動說。
    # The user consented to an overwrite, not to destruction: say where it went.
    case "$occupant_output" in
        *"--restore"*) ;;
        *) occupant_ok=0 ;;
    esac
    case "$occupant_kind" in
        file|hardlink)
            if [ ! -f occupant.txt ] || [ -L occupant.txt ] ||
               [ "$(cat occupant.txt 2>/dev/null)" != "OCCUPANT CONTENT" ]; then
                occupant_ok=0
            fi
            ;;
        symlink)
            # 連結本身進垃圾桶，絕不跟隨：指向的檔案必須原封不動留在原處。
            # The link itself is trashed and never followed: its target stays put.
            if [ ! -L occupant.txt ] ||
               [ "$(readlink occupant.txt)" != "occupant_link_target.txt" ] ||
               [ "$(cat occupant_link_target.txt 2>/dev/null)" != "BYSTANDER CONTENT" ]; then
                occupant_ok=0
            fi
            ;;
        symlink-to-dir)
            if [ ! -L occupant.txt ] ||
               [ "$(readlink occupant.txt)" != "occupant_link_dir" ] ||
               [ "$(cat occupant_link_dir/inside.txt 2>/dev/null)" != "BYSTANDER CONTENT" ]; then
                occupant_ok=0
            fi
            ;;
        empty-dir)
            if [ ! -d occupant.txt ] || [ -L occupant.txt ] ||
               [ -n "$(ls -A occupant.txt 2>/dev/null)" ]; then
                occupant_ok=0
            fi
            ;;
        non-empty-dir)
            if [ ! -d occupant.txt ] || [ -L occupant.txt ] ||
               [ "$(cat occupant.txt/keep.txt 2>/dev/null)" != "OCCUPANT CONTENT" ]; then
                occupant_ok=0
            fi
            ;;
    esac
    # hardlink 的另一端不屬於這次覆蓋，必須完全不受影響。
    # The other end of a hardlink is not part of this overwrite and must not move.
    if [ "$occupant_kind" = "hardlink" ] &&
       [ "$(cat occupant_peer.txt 2>/dev/null)" != "OCCUPANT CONTENT" ]; then
        occupant_ok=0
    fi

    if [ "$occupant_ok" -eq 1 ]; then
        test_pass "既有的 $occupant_kind 讓位進垃圾桶，還原完成且讓位物件仍可還原"
    else
        test_fail "既有的 $occupant_kind 被銷毀或無法再還原 (status=$occupant_status, back=$occupant_back_status, trashed=$occupant_trashed, litter=$occupant_litter)"
    fi
done

test_item "還原：讓位物件的名字在垃圾桶已經有紀錄時，兩筆都必須留得住"
# 讓位走的是 move_to_trash，垃圾桶路徑由「原始路徑＋時間戳＋hash」組成，同一個原始
# 路徑被刪過好幾次時就得靠既有的唯一化機制錯開。若讓位那一筆覆蓋掉先前的紀錄或項目，
# 使用者會在「還原一次」之後永久失去更早的那一份——而他根本沒有要求刪掉它。
# The set-aside goes through move_to_trash, whose trash path is the original path
# plus a timestamp and a hash, so several deletions of one path rely on the
# existing uniquification to stay apart. If the set-aside clobbered an earlier
# record or item, one restore would permanently destroy an earlier version the
# user never asked to remove.
setup
cd "$TEST_WORK_DIR" || exit 1
printf '%s\n' "OLDER TRASHED" > collide.txt
"$BETTER_RM" collide.txt
printf '%s\n' "NEWER TRASHED" > collide.txt
"$BETTER_RM" collide.txt
printf '%s\n' "COLLIDE OCCUPANT" > collide.txt
collide_status=0
"$BETTER_RM" -f --restore collide.txt >/dev/null 2>&1 || collide_status=$?
collide_entries=$(find "$TEST_TRASH_DIR" -maxdepth 6 -name 'collide.txt__*' 2>/dev/null | wc -l | tr -d ' ')
collide_first=$(cat collide.txt 2>/dev/null)
# 讓位那一筆是最新的，先回來；再還原一次就必須拿到更早的那一筆。
# The set-aside entry is the newest and comes back first; the restore after it
# must hand back the older entry that was already in the trash.
collide_second_status=0
mv collide.txt collide_newer_away.txt 2>/dev/null
"$BETTER_RM" --restore collide.txt >/dev/null 2>&1 || collide_second_status=$?
collide_second=$(cat collide.txt 2>/dev/null)
collide_third_status=0
mv collide.txt collide_occupant_away.txt 2>/dev/null
"$BETTER_RM" --restore collide.txt >/dev/null 2>&1 || collide_third_status=$?
collide_third=$(cat collide.txt 2>/dev/null)

if [ "$collide_status" -eq 0 ] && \
   [ "$collide_second_status" -eq 0 ] && \
   [ "$collide_third_status" -eq 0 ] && \
   [ "$collide_entries" -eq 2 ] && \
   [ "$collide_first" = "NEWER TRASHED" ] && \
   [ "$collide_second" = "COLLIDE OCCUPANT" ] && \
   [ "$collide_third" = "OLDER TRASHED" ]; then
    test_pass "讓位那一筆與既有的同名紀錄各自獨立，三份資料依序都還原得回來"
else
    test_fail "同名紀錄相撞時遺失其中一份 (entries=$collide_entries, 1='$collide_first', 2='$collide_second', 3='$collide_third')"
fi

test_item "還原：檔案讓位到垃圾桶失敗時改用就地讓位，絕不可就這樣把它覆蓋掉"
# 垃圾桶暫時寫不進去時，舊目的地若確實還是那個已驗證的物件，就沿用既有的就地讓位
# 退路（同裝置 rename，不需要空間），使用者同意過的覆蓋照樣完成，而舊目的地一樣不會
# 被銷毀。這條退路先前只有真目錄的目的地走得到；一般檔案是直接被 rename 蓋掉。
# When the trash is momentarily unwritable and the old destination really is still
# the verified object, the existing in-place route (a same-device rename, needing
# no space) still applies: the consented overwrite completes and the destination is
# still not destroyed. Only a real-directory destination used to reach that route;
# a plain file was simply overwritten by the rename.
setup
cd "$TEST_WORK_DIR" || exit 1
filefail_bin="$TEST_WORK_DIR/restore-filefail-bin"
mkdir -p "$filefail_bin"
cat > "$filefail_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
# 只讓「把東西搬進垃圾桶」這一次失敗；從垃圾桶取出不受影響。
# Fail only the move INTO the trash; taking things out of it is unaffected.
case "$dst" in
  "$BETTER_RM_FILEFAIL_TRASH"/*)
    case "$src" in
      "$BETTER_RM_FILEFAIL_TRASH"/*) exec "$BETTER_RM_REAL_MV" "$@" ;;
      *) exit 1 ;;
    esac
    ;;
esac
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$filefail_bin/mv"

printf '%s\n' "FILEFAIL RESTORED" > filefail.txt
"$BETTER_RM" filefail.txt
printf '%s\n' "FILEFAIL OCCUPANT" > filefail.txt
filefail_status=0
filefail_output=$(BETTER_RM_FILEFAIL_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$filefail_bin:$PATH" \
    "$BETTER_RM" -f --restore filefail.txt 2>&1) || filefail_status=$?
filefail_aside=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'filefail.txt.better-rm-displaced-*' -print -quit)

# 就地讓位是降級結果，結束碼是 2 而不是 0（見下面「降級結果」那一項）。
# The in-place set-aside is a degraded outcome and exits 2, not 0 (see the
# "degraded outcome" item below).
if [ "$filefail_status" -eq 2 ] && \
   [ -f filefail.txt ] && [ ! -L filefail.txt ] && \
   [ "$(cat filefail.txt)" = "FILEFAIL RESTORED" ] && \
   [ -n "$filefail_aside" ] && \
   [ "$(cat "$filefail_aside/filefail.txt" 2>/dev/null)" = "FILEFAIL OCCUPANT" ] && \
   [[ "$filefail_output" == *"$filefail_aside"* ]]; then
    test_pass "檔案讓位到垃圾桶失敗時改用就地讓位，舊目的地完好並被指名"
else
    test_fail "檔案讓位到垃圾桶失敗時舊目的地被銷毀或沒說去向 (status=$filefail_status, aside='$filefail_aside')"
fi

test_item "還原：就地讓位是降級結果，結束碼不得與乾淨完成相同，落腳處也要印在 stdout"
# 就地讓位保住了資料，但它是降級的結果，不是乾淨的完成：讓位的那一個躺在垃圾桶外面、
# 也不在刪除日誌裡，`rm --restore` 對它完全無效，收拾它是使用者的事。這條退路現在檔案、
# 符號連結、硬連結、FIFO 都走得到，觸發條件也從「垃圾桶那顆磁碟滿了」放寬到一般的權限
# 失敗，所以它不再是罕見角落。實測改動前：exit 0、stdout 0 bytes，唯一的線索只在 stderr。
# 對一個把 stderr 丟掉的呼叫端（`rm -f --restore x 2>/dev/null`、CI step、包一層的腳本）
# 來說，這與什麼事都沒發生的成功完全無法區分，而它得自己去收的那個目錄叫什麼，它永遠
# 不會知道。所以：結束碼走既有的 2（「部分成功、殘留物已指名、絕不回 0」，與暫存目錄
# 沒清掉時同一個意思），路徑同時印在 stdout。
# stdout 那兩行刻意不上色也不走 warn_msg：它是給呼叫端讀的資料，不是給人看的裝飾。
# The in-place set-aside keeps the data, but it is a degraded outcome rather than a
# clean completion: the displaced object sits OUTSIDE the trash and outside the
# deletion log, `rm --restore` cannot reach it, and clearing it up is the user's
# job. Files, symlinks, hardlinks and FIFOs all reach this route now, and it is
# entered from ordinary permission failures rather than only from a full trash
# volume, so it is no longer a rare corner. Measured before this change: exit 0 and
# 0 bytes of stdout, with the only trace on stderr. To a caller that discards stderr
# (`rm -f --restore x 2>/dev/null`, a CI step, any wrapper) that is indistinguishable
# from a clean success, and the directory it now has to clean up is one it can never
# learn the name of. So: the exit code becomes the existing 2 -- "partial success,
# the residue is named, never 0", the same meaning it already has for a staging
# directory that could not be removed -- and the path is printed on stdout as well.
# Those stdout lines are deliberately uncoloured and not warn_msg: they are data for
# a caller, not decoration for a human.
setup
cd "$TEST_WORK_DIR" || exit 1
loud_bin="$TEST_WORK_DIR/restore-loud-bin"
mkdir -p "$loud_bin"
cat > "$loud_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
# 只讓「把東西搬進垃圾桶」這一次失敗；從垃圾桶取出不受影響。
# Fail only the move INTO the trash; taking things out of it is unaffected.
case "$dst" in
  "$BETTER_RM_LOUD_TRASH"/*)
    case "$src" in
      "$BETTER_RM_LOUD_TRASH"/*) exec "$BETTER_RM_REAL_MV" "$@" ;;
      *) exit 1 ;;
    esac
    ;;
esac
exec "$BETTER_RM_REAL_MV" "$@"
EOF
chmod +x "$loud_bin/mv"

printf '%s\n' "LOUD RESTORED" > loud.txt
"$BETTER_RM" loud.txt
printf '%s\n' "LOUD OCCUPANT" > loud.txt
loud_status=0
BETTER_RM_LOUD_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_MV="$(command -v mv)" \
PATH="$loud_bin:$PATH" \
    "$BETTER_RM" -f --restore loud.txt \
    > "$TEST_WORK_DIR/loud.out" 2> "$TEST_WORK_DIR/loud.err" || loud_status=$?
loud_out=$(cat "$TEST_WORK_DIR/loud.out")
loud_err=$(cat "$TEST_WORK_DIR/loud.err")
loud_aside=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'loud.txt.better-rm-displaced-*' -print -quit)

# 負對照：乾淨完成的那條路徑必須維持 exit 0，而且 stdout 不得冒出讓位訊息。少了這一列，
# 「一律回 2、一律印」也會通過，那是比原本更糟的退化。
# Negative control: the clean route must still exit 0 with no set-aside line on
# stdout. Without this row, "always return 2 and always print" would also pass,
# which is a worse regression than the silence was.
printf '%s\n' "QUIET RESTORED" > quiet.txt
"$BETTER_RM" quiet.txt
printf '%s\n' "QUIET OCCUPANT" > quiet.txt
quiet_status=0
"$BETTER_RM" -f --restore quiet.txt > "$TEST_WORK_DIR/quiet.out" 2>/dev/null || quiet_status=$?
quiet_out=$(cat "$TEST_WORK_DIR/quiet.out")

if [ "$loud_status" -eq 2 ] && \
   [ -n "$loud_aside" ] && \
   [[ "$loud_out" == *"$loud_aside/loud.txt"* ]] && \
   [[ "$loud_err" == *"$loud_aside/loud.txt"* ]] && \
   [ "$(cat loud.txt)" = "LOUD RESTORED" ] && \
   [ "$(cat "$loud_aside/loud.txt" 2>/dev/null)" = "LOUD OCCUPANT" ] && \
   [ "$quiet_status" -eq 0 ] && \
   [[ "$quiet_out" != *"better-rm-displaced"* ]] && \
   [ "$(cat quiet.txt)" = "QUIET RESTORED" ]; then
    test_pass "就地讓位回傳 2 並在 stdout 指名落腳處，乾淨完成的那條路徑仍是 0 且不多話"
else
    test_fail "降級的就地讓位與乾淨完成無法區分 (讓位 status=$loud_status, stdout='$loud_out', aside='$loud_aside'；乾淨 status=$quiet_status, stdout='$quiet_out')"
fi

test_item "還原：讓位物件本身受保護時，整個還原必須中止且目的地一動也不能動"
# 受保護的路徑不能被移進垃圾桶（原則性拒絕），也不能改走就地讓位（那等於自己拆掉
# 保護）。兩條路都不通時唯一正確的行為是中止：目的地保持原樣、垃圾桶項目放回原處、
# 結束碼非 0。這正是 fail-closed 的形狀——沒有任何一步先動了目的地才發現讓不了位。
# 訊息也必須說出真正的原因；同樣非 0 的「找不到紀錄」是完全不同的事，不能混為一談。
# A protected path can be neither moved into the trash (a refusal on principle) nor
# routed around by the in-place set-aside, which would dismantle the protection.
# With both routes closed the only correct behaviour is to abort: the destination
# untouched, the trashed item put back, a nonzero exit. That is the fail-closed
# shape -- nothing touches the destination before the set-aside is known to work.
# The message must state the real reason, too: an equally nonzero "no record found"
# is a different event and must not be mistaken for this one.
setup
cd "$TEST_WORK_DIR" || exit 1
# better-rm 自己不會把 .git 移入垃圾桶（那正是保護的用意），所以紀錄與垃圾桶項目
# 直接造出來，才能測到「還原一個受保護名稱到既有的同名檔案上」。
# better-rm will not trash a .git itself -- that is the protection -- so the record
# and the trashed item are fabricated to reach "restore a protected name over an
# existing file of the same name".
mkdir -p "$TEST_TRASH_DIR$TEST_WORK_DIR"
protfile_trash="$TEST_TRASH_DIR$TEST_WORK_DIR/.git__20260101_000000_000000000__nohash"
printf '%s\n' "PROTFILE ORIGINAL" > "$protfile_trash"
mkdir -p "$TEST_STATE_DIR"
{
    printf '%s\n' "# Better-RM Deletion Log"
    printf '%s | %s | %s | %s | %s\n' \
        "20260101_000000_000000000" \
        "$TEST_WORK_DIR/.git" \
        "$protfile_trash" \
        "nohash" \
        "file"
} > "$TEST_STATE_DIR/deletion.log"
printf '%s\n' "PROTFILE DESTINATION" > .git
protfile_status=0
protfile_output=$("$BETTER_RM" -f --restore .git 2>&1) || protfile_status=$?
protfile_litter=$(find "$TEST_WORK_DIR" -maxdepth 1 -name '.git.better-rm-*' 2>/dev/null | wc -l | tr -d ' ')

if [ "$protfile_status" -ne 0 ] && \
   [ -f .git ] && [ ! -L .git ] && \
   [ "$(cat .git)" = "PROTFILE DESTINATION" ] && \
   [ -f "$protfile_trash" ] && \
   [ "$(cat "$protfile_trash")" = "PROTFILE ORIGINAL" ] && \
   [ "$protfile_litter" -eq 0 ] && \
   [[ "$protfile_output" == *"讓位"* ]]; then
    test_pass "受保護的讓位物件讓還原整個中止，目的地與垃圾桶項目都沒被動到"
else
    test_fail "受保護的讓位物件被銷毀、被搬走或中止原因說錯 (status=$protfile_status, litter=$protfile_litter)"
fi

test_item "還原：垃圾桶與目的地不同檔案系統時，讓位物件一樣要進垃圾桶"
# 跨裝置時「讓位＝移進垃圾桶」是一次完整複製，比同裝置的 rename 慢也更容易失敗——
# 但它一樣不可以退化成「直接覆蓋掉」。這裡用既有的兩支 shim 重現決定性性質（垃圾桶
# 子樹回報不同 device、從垃圾桶取出改以 copy+unlink 執行）。
# Across devices the set-aside is a full copy rather than a rename: slower and more
# failure-prone, but it still must not degrade into "just overwrite it". The two
# existing shims reproduce the decisive properties (the trash subtree reports a
# different device; extraction from the trash runs as copy+unlink).
setup
cd "$TEST_WORK_DIR" || exit 1
xdevocc_bin="$TEST_WORK_DIR/restore-xdevocc-bin"
make_xdev_stat_shim "$xdevocc_bin"
cat > "$xdevocc_bin/mv" <<'EOF'
#!/bin/sh
count=$#
i=0
src=""
dst=""
for a in "$@"; do
    i=$((i + 1))
    if [ "$i" -eq $((count - 1)) ]; then src="$a"; fi
    if [ "$i" -eq "$count" ]; then dst="$a"; fi
done
case "$src" in
  "$BETTER_RM_XDEV_TRASH"/*) ;;
  *) exec "$BETTER_RM_REAL_MV" "$@" ;;
esac
if [ -e "$dst" ] || [ -L "$dst" ]; then exec "$BETTER_RM_REAL_MV" "$@"; fi
cp -R "$src" "$dst" || exit 1
"$BETTER_RM_REAL_RM" -rf "$src" || exit 1
exit 0
EOF
chmod +x "$xdevocc_bin/mv"

printf '%s\n' "XDEVOCC RESTORED" > xdevocc.txt
"$BETTER_RM" xdevocc.txt
printf '%s\n' "XDEVOCC OCCUPANT" > xdevocc.txt
xdevocc_status=0
BETTER_RM_XDEV_TRASH="$TEST_TRASH_DIR" \
BETTER_RM_REAL_STAT="$(command -v stat)" \
BETTER_RM_REAL_MV="$(command -v mv)" \
BETTER_RM_REAL_RM="$(command -v rm)" \
PATH="$xdevocc_bin:$PATH" \
    "$BETTER_RM" -f --restore xdevocc.txt >/dev/null 2>&1 || xdevocc_status=$?
xdevocc_litter=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'xdevocc.txt.better-rm-*' 2>/dev/null | wc -l | tr -d ' ')
# 沒有 shim 的第二次還原必須把讓位物件交回來：那需要一筆真的 deletion log 紀錄。
# A second restore without the shims must hand the occupant back, which needs a
# real deletion-log record.
xdevocc_back_status=0
mv xdevocc.txt xdevocc_restored_away.txt 2>/dev/null
"$BETTER_RM" --restore xdevocc.txt >/dev/null 2>&1 || xdevocc_back_status=$?

if [ "$xdevocc_status" -eq 0 ] && \
   [ "$xdevocc_back_status" -eq 0 ] && \
   [ "$(cat xdevocc_restored_away.txt 2>/dev/null)" = "XDEVOCC RESTORED" ] && \
   [ "$(cat xdevocc.txt 2>/dev/null)" = "XDEVOCC OCCUPANT" ] && \
   [ "$xdevocc_litter" -eq 0 ]; then
    test_pass "跨裝置還原時讓位物件進了垃圾桶，兩份資料都在且都還原得回來"
else
    test_fail "跨裝置還原銷毀了讓位物件 (status=$xdevocc_status, back=$xdevocc_back_status, litter=$xdevocc_litter)"
fi

test_item "還原：互動確認回答 n 時，垃圾桶項目與既有目的地都不得被動到"
# 沒有 -f 的覆蓋要先問過使用者。回答 n 就是什麼都不做：目的地留在原地、垃圾桶項目
# 也不能被消耗掉（否則下一次 --restore 會說找不到）。
# An overwrite without -f asks first. Answering n does nothing at all: the
# destination stays and the trashed item must not be consumed, or the next
# --restore reports it as missing.
setup
cd "$TEST_WORK_DIR" || exit 1
printf '%s\n' "PROMPT RESTORED" > prompt.txt
"$BETTER_RM" prompt.txt
printf '%s\n' "PROMPT OCCUPANT" > prompt.txt
promptn_status=0
echo "n" | "$BETTER_RM" --restore prompt.txt >/dev/null 2>&1 || promptn_status=$?
promptn_entries=$(find "$TEST_TRASH_DIR" -maxdepth 6 -name 'prompt.txt__*' 2>/dev/null | wc -l | tr -d ' ')
promptn_litter=$(find "$TEST_WORK_DIR" -maxdepth 1 -name 'prompt.txt.better-rm-*' 2>/dev/null | wc -l | tr -d ' ')

if [ "$promptn_status" -eq 0 ] && \
   [ "$(cat prompt.txt)" = "PROMPT OCCUPANT" ] && \
   [ "$promptn_entries" -eq 1 ] && \
   [ "$promptn_litter" -eq 0 ]; then
    test_pass "回答 n 時還原沒有發生，兩邊都原封不動"
else
    test_fail "回答 n 時仍動了目的地或垃圾桶 (status=$promptn_status, entries=$promptn_entries, litter=$promptn_litter)"
fi

test_item "還原：互動確認回答 y 時，被覆蓋的目的地同樣要進垃圾桶"
# 同意覆蓋跟 -f 是同一件事——差別只在同意是怎麼取得的，不在被覆蓋的那個物件值不值得
# 保留。回答 y 之後舊目的地一樣必須可以用 rm --restore 取回。
# Consenting at the prompt is the same act as -f: what differs is how the consent
# was obtained, not whether the overwritten object is worth keeping. After a y the
# old destination must be recoverable with rm --restore just the same.
prompty_status=0
echo "y" | "$BETTER_RM" --restore prompt.txt >/dev/null 2>&1 || prompty_status=$?
prompty_back_status=0
mv prompt.txt prompt_restored_away.txt 2>/dev/null
"$BETTER_RM" --restore prompt.txt >/dev/null 2>&1 || prompty_back_status=$?

if [ "$prompty_status" -eq 0 ] && \
   [ "$prompty_back_status" -eq 0 ] && \
   [ "$(cat prompt_restored_away.txt 2>/dev/null)" = "PROMPT RESTORED" ] && \
   [ "$(cat prompt.txt 2>/dev/null)" = "PROMPT OCCUPANT" ]; then
    test_pass "回答 y 的覆蓋與 -f 一致，舊目的地進垃圾桶且還原得回來"
else
    test_fail "回答 y 時舊目的地被銷毀 (status=$prompty_status, back=$prompty_back_status)"
fi

test_item "含 | 的檔名可完整刪除並還原"
# 日誌以 | 分隔且還原時逐一切開，合法檔名裡的 | 會讓紀錄無法被解析。
# The pipe-delimited log cannot represent a legal filename containing '|',
# so restore could not find its own record.
setup
cd "$TEST_WORK_DIR"
printf '%s\n' "PIPE CONTENT" > 'a|b.txt'
"$BETTER_RM" 'a|b.txt'
pipe_restore_status=0
"$BETTER_RM" --restore 'a|b.txt' >/dev/null 2>&1 || pipe_restore_status=$?
if [ "$pipe_restore_status" -eq 0 ] && [ -f 'a|b.txt' ] && \
   [ "$(cat 'a|b.txt')" = "PIPE CONTENT" ]; then
    test_pass "含 | 的檔名往返還原成功"
else
    test_fail "含 | 的檔名無法還原 (status=$pipe_restore_status)"
fi

test_item "含換行的檔名可完整刪除並還原"
# 原始路徑直接寫進單行日誌，檔名裡的換行會把一筆紀錄拆成兩行。
# A raw newline in the path splits one record into two log lines.
setup
cd "$TEST_WORK_DIR"
newline_name=$'nl\nname.txt'
printf '%s\n' "NEWLINE CONTENT" > "$newline_name"
"$BETTER_RM" "$newline_name"
newline_restore_status=0
"$BETTER_RM" --restore "$newline_name" >/dev/null 2>&1 || newline_restore_status=$?
if [ "$newline_restore_status" -eq 0 ] && [ -f "$newline_name" ] && \
   [ "$(cat "$newline_name")" = "NEWLINE CONTENT" ]; then
    test_pass "含換行的檔名往返還原成功"
else
    test_fail "含換行的檔名無法還原 (status=$newline_restore_status)"
fi

test_item "以換行結尾的檔名可完整刪除並還原"
# basename／dirname 走命令替換，而命令替換會吃掉所有結尾換行：釘住的 ./basename
# 於是指向另一個名字，inode 對不上，刪除以「在固定 parent 前已變更；未移動」中止
# ——fail-safe，但那個檔案變成刪不掉。中間有換行的可以（上面那則），結尾有的不行，
# 而 README 承諾含換行的檔名會被正確記錄與還原。
# basename/dirname run through command substitution, which strips every trailing
# newline: the pinned ./basename then names a different file, the inode does not
# match and the delete aborts with "changed before its parent was pinned; not
# moved" -- fail-safe, but the file becomes undeletable. A newline in the middle
# works (the case above), one at the end did not, and README promises
# newline-containing names are recorded and restored.
setup
cd "$TEST_WORK_DIR"
trailing_nl_name=$'trail.txt\n'
printf '%s\n' "TRAILING NEWLINE CONTENT" > "$trailing_nl_name"
trailing_nl_delete_status=0
"$BETTER_RM" "$trailing_nl_name" >/dev/null 2>&1 || trailing_nl_delete_status=$?
trailing_nl_restore_status=0
"$BETTER_RM" --restore "$trailing_nl_name" >/dev/null 2>&1 || trailing_nl_restore_status=$?
if [ "$trailing_nl_delete_status" -eq 0 ] && [ "$trailing_nl_restore_status" -eq 0 ] && \
   [ -f "$trailing_nl_name" ] && \
   [ "$(cat "$trailing_nl_name")" = "TRAILING NEWLINE CONTENT" ]; then
    test_pass "以換行結尾的檔名往返還原成功"
else
    test_fail "以換行結尾的檔名無法往返 (delete=$trailing_nl_delete_status, restore=$trailing_nl_restore_status)"
fi

test_item "以斜線結尾的目錄寫法仍照舊處理"
# 取代 basename 的參數展開必須自己剝掉結尾斜線：basename "dir/" 是 dir，而
# "${path##*/}" 是空字串。`rm -r dir/` 是常見寫法，沒有這一步就會拿到空的名字。
# The parameter expansion that replaced basename has to strip trailing slashes on
# its own: basename "dir/" is dir while "${path##*/}" is the empty string, and
# naming a directory with a trailing slash is an everyday spelling.
setup
cd "$TEST_WORK_DIR"
mkdir -p slashdir/sub
echo "SLASH CONTENT" > slashdir/sub/f.txt
slash_status=0
"$BETTER_RM" -r slashdir/ >/dev/null 2>&1 || slash_status=$?
if [ "$slash_status" -eq 0 ] && [ ! -e slashdir ] && verify_in_trash "slashdir"; then
    test_pass "以斜線結尾的目錄可正常刪除"
else
    test_fail "以斜線結尾的目錄刪除失敗 (status=$slash_status)"
fi

test_item "parent 是根目錄時記下的路徑不得多一條斜線"
# abs_path 由「實體 parent + 最後一段」組成，而 parent 是 "/" 時直接接斜線會得到
# //name。那個字串會原封不動寫進刪除日誌與垃圾桶鏡像路徑，記下來的寫法就跟使用者
# 指名的不一樣。
# 為什麼不端到端驗：要讓 pinned parent 的 pwd -P 等於 "/"，來源必須是 / 底下一個真實
# 的項目，而兩個目標平台都不允許測試建立這種東西——macOS 的系統卷是封裝唯讀，CI 的
# ubuntu runner 上 / 由 root 擁有（實測 [ -w / ] 皆為否）。/ 底下的項目本身沒有被
# is_protected 擋掉（實測 `better-rm /不存在` 停在「沒有此一檔案或目錄」，不是「受
# 保護」），所以這條路徑對寫得進 / 的人是走得到的。
# 折衷是直接從 better-rm 抽出組路徑的那個函式來驗：抽的是檔案裡真正在跑的那一份。
# abs_path is composed from the physical parent plus the final component, and a
# "/" parent given another slash yields //name -- a string that goes verbatim into
# the deletion log and the trash mirror path, spelled differently from what the
# user named.
# Why this is not end-to-end: making the pinned parent's pwd -P equal "/" requires
# a real entry directly under /, and neither target platform lets a test create
# one (macOS ships a sealed read-only system volume; / on the ubuntu CI runner is
# root-owned -- [ -w / ] is false on both). Entries under / are not themselves
# refused by is_protected (`better-rm /does-not-exist` stops at "No such file or
# directory", not at "protected"), so the path is reachable for anyone who can
# write to /.
# So the join is exercised directly, extracted from better-rm itself, which means
# the function under test is the one that actually ships.
setup
eval "$(sed -n '/^path_join() {$/,/^}$/p' "$BETTER_RM")"
join_failures=""
for join_case in "/|name|/name" "/parent|name|/parent/name" "/parent/|name|/parent/name"; do
    join_parent="${join_case%%|*}"
    join_rest="${join_case#*|}"
    join_child="${join_rest%%|*}"
    join_expected="${join_rest#*|}"
    PATH_JOIN_RESULT=""
    path_join "$join_parent" "$join_child"
    if [ "$PATH_JOIN_RESULT" != "$join_expected" ]; then
        join_failures="$join_failures '$join_parent'+'$join_child'=>'$PATH_JOIN_RESULT' (期望 $join_expected)"
    fi
done
if [ -z "$join_failures" ]; then
    test_pass "根目錄 parent 組出單一斜線的絕對路徑"
else
    test_fail "組出的絕對路徑有誤：$join_failures"
fi

test_item "含雙斜線的既有日誌紀錄仍可還原"
# 上一版曾把 / 底下的來源記成 //name。那些紀錄不會因為改回單斜線而失效。
# 真正寫出過雙斜線的那一版（2efbeee）寫的是 v2 六欄格式，所以主要要釘的是 v2；
# 舊版五欄一併保留，因為升級前的紀錄也可能帶著同樣的路徑。
# The previous revision recorded a source under / as //name. Those records must
# keep restoring after the composition goes back to a single slash. The revision
# that actually emitted doubled slashes wrote v2 six-field records, so v2 is the
# shape that matters here; the legacy five-field layout is kept alongside it
# because pre-upgrade records can carry the same paths.
double_slash_ok=1
for ledger_format in v2 legacy; do
    setup
    cd "$TEST_WORK_DIR"
    printf '%s\n' "DOUBLE SLASH LEDGER" > double_slash.txt
    "$BETTER_RM" double_slash.txt
    double_slash_trash=$(find "$TEST_TRASH_DIR" -type f -name 'double_slash.txt__*' | head -1)
    {
        printf '%s\n' "# Better-RM Deletion Log"
        if [ "$ledger_format" = "v2" ]; then
            printf '%s | v2 | %s | %s | %s | %s\n' \
                "20260101_000000_000000000" \
                "/${TEST_WORK_DIR}/double_slash.txt" \
                "$double_slash_trash" \
                "0123456789abcdef" \
                "file"
        else
            printf '%s | %s | %s | %s | %s\n' \
                "20260101_000000_000000000" \
                "/${TEST_WORK_DIR}/double_slash.txt" \
                "$double_slash_trash" \
                "0123456789abcdef" \
                "file"
        fi
    } > "$TEST_STATE_DIR/deletion.log"
    double_slash_status=0
    "$BETTER_RM" --restore double_slash.txt >/dev/null 2>&1 || double_slash_status=$?
    if [ "$double_slash_status" -ne 0 ] || [ ! -f double_slash.txt ] || \
       [ "$(cat double_slash.txt)" != "DOUBLE SLASH LEDGER" ]; then
        double_slash_ok=0
        printf '  %s 格式的雙斜線紀錄無法還原 / a %s doubled-slash record did not restore (status=%s)\n' \
            "$ledger_format" "$ledger_format" "$double_slash_status" >&2
    fi
done
if [ "$double_slash_ok" -eq 1 ]; then
    test_pass "v2 與舊版格式的雙斜線紀錄都還原成功"
else
    test_fail "雙斜線紀錄無法還原"
fi

test_item "升級前寫下的舊格式日誌仍可還原"
# 本機既有的垃圾桶紀錄都是舊格式；新格式必須照樣讀得懂，否則升級即斷。
# Trash logs written before this change are in the old format; the reader must
# keep understanding them or upgrading breaks restore of already-trashed items.
setup
cd "$TEST_WORK_DIR"
printf '%s\n' "OLD FORMAT" > old_format.txt
"$BETTER_RM" old_format.txt
old_format_trash=$(find "$TEST_TRASH_DIR" -type f -name 'old_format.txt__*' | head -1)
{
    printf '%s\n' "# Better-RM Deletion Log"
    printf '%s | %s | %s | %s | %s\n' \
        "20260101_000000_000000000" \
        "$TEST_WORK_DIR/old_format.txt" \
        "$old_format_trash" \
        "0123456789abcdef" \
        "file"
} > "$TEST_STATE_DIR/deletion.log"
old_format_status=0
"$BETTER_RM" --restore old_format.txt >/dev/null 2>&1 || old_format_status=$?
if [ "$old_format_status" -eq 0 ] && [ -f old_format.txt ] && \
   [ "$(cat old_format.txt)" = "OLD FORMAT" ]; then
    test_pass "舊格式日誌紀錄仍可還原"
else
    test_fail "舊格式日誌紀錄無法還原 (status=$old_format_status)"
fi

test_item "長日誌的還原掃描不得退化（效能護欄）"
# 日誌只增不減，還原舊項目要掃過全部紀錄。若每一筆都付出解碼／fork 成本，
# 成本會隨日誌長度單調惡化。門檻刻意放寬，只攔「數量級」等級的退化：
# 同樣的 2000 筆 / 450 字元路徑，退化版本要 17 秒，修好後約 0.2 秒。
# The log is append-only, so restoring an old item scans every record. Paying a
# decode or a fork per record degrades monotonically with log length. The budget
# is deliberately loose: it only catches an order-of-magnitude regression
# (17s versus roughly 0.2s for the same 2000 records with 450-char paths).
setup
mkdir -p "$TEST_TRASH_DIR" "$TEST_STATE_DIR"
cd "$TEST_WORK_DIR"
perf_prefix="/perf/scan/deeply/nested/workspace/module/component/service/handler/internal/pkg/adapters/persistence/repository/generated/artifacts/build/output/cache/segments/shards"
while [ ${#perf_prefix} -lt 420 ]; do perf_prefix="$perf_prefix/more"; done
perf_target="perf-scan-target.txt"
perf_trash="$TEST_TRASH_DIR/${perf_target}__oldest"
printf '%s\n' "PERF SCAN CONTENT" > "$perf_trash"
{
    printf '%s\n' "# Better-RM Deletion Log"
    # 最舊的一筆放最前面：掃描由尾端往回，因此這筆最後才被讀到。
    # Oldest record first: the scan walks backwards, so this one is reached last.
    printf '%s | v2 | %s | %s | %s | %s\n' \
        "20260101_000000_000000000" "$perf_prefix/$perf_target" "$perf_trash" \
        "deadbeefdeadbeefdeadbeefdeadbeef" "file"
    awk -v prefix="$perf_prefix" -v trash="$TEST_TRASH_DIR" 'BEGIN {
        for (i = 1; i < 2000; i++) {
            name = sprintf("perf-filler-%06d.txt", i)
            printf "20260102_%06d_000000000 | v2 | %s/%s | %s/%s__%d__missing | %s | file\n", \
                i, prefix, name, trash, name, i, "0123456789abcdef0123456789abcdef"
        }
    }'
} > "$TEST_STATE_DIR/deletion.log"
perf_start=$SECONDS
perf_status=0
"$BETTER_RM" --restore "$perf_target" >/dev/null 2>&1 || perf_status=$?
perf_elapsed=$((SECONDS - perf_start))
if [ "$perf_status" -eq 0 ] && [ -f "$perf_target" ] && \
   [ "$(cat "$perf_target")" = "PERF SCAN CONTENT" ] && \
   [ "$perf_elapsed" -le 10 ]; then
    test_pass "2000 筆長路徑日誌的全掃描還原在門檻內完成 (${perf_elapsed}s)"
else
    test_fail "長日誌還原退化或失敗 (status=$perf_status, elapsed=${perf_elapsed}s)"
fi

# 清理測試產生的檔案
rm -f test_restore.txt

# ============================================================================
# 測試 14: 保留鎖目錄的清理與互斥 (Test 14: Reservation lock cleanup & mutex)
# ============================================================================
test_title "測試 14: 保留鎖目錄的清理與碰撞互斥"

setup
cd "$TEST_WORK_DIR" || exit 1

test_item "成功刪除後不留下 .reserve 保留鎖目錄"
printf '%s\n' "reserve cleanup content" > reserve-cleanup.txt
"$BETTER_RM" reserve-cleanup.txt
leftover_reserve=$(find "$TEST_TRASH_DIR" -type d -name '*.reserve' 2>/dev/null | wc -l | tr -d ' ')
if [ ! -e reserve-cleanup.txt ] && [ "$leftover_reserve" -eq 0 ]; then
    test_pass "成功路徑清除了保留鎖目錄"
else
    test_fail "成功刪除後殘留 .reserve 保留鎖目錄（找到 $leftover_reserve）"
fi

test_item "保留鎖被並發持有時改用 suffixed 目標（mkdir 互斥）"
setup
cd "$TEST_WORK_DIR" || exit 1
reserve_mutex_bin="$TEST_WORK_DIR/reserve-mutex-bin"
mkdir -p "$reserve_mutex_bin"
cat > "$reserve_mutex_bin/date" <<'EOF'
#!/bin/sh
printf '%s\n' '20260724_120000_000000000'
EOF
cat > "$reserve_mutex_bin/md5sum" <<'EOF'
#!/bin/sh
printf '%s  -\n' 'deadbeefdeadbeefdeadbeefdeadbeef'
EOF
chmod +x "$reserve_mutex_bin/date" "$reserve_mutex_bin/md5sum"

printf '%s\n' "mutex content" > reserve-mutex.txt
# 以 better-rm 相同方式解析絕對路徑，重建其固定的 base_target。
# Resolve the absolute path exactly as better-rm does to rebuild its fixed base_target.
mutex_abs_src=$(readlink -f reserve-mutex.txt 2>/dev/null || realpath reserve-mutex.txt 2>/dev/null)
mutex_base_target="$TEST_TRASH_DIR$mutex_abs_src"'__20260724_120000_000000000__deadbeefdeadbeefdeadbeefdeadbeef'
mkdir -p "$(dirname "$mutex_base_target")"
# 模擬另一個 better-rm 已保留 attempt-0 的鎖目錄，但尚未建立目標檔。
# Simulate a concurrent better-rm holding the attempt-0 reservation but not yet the target.
mkdir "$mutex_base_target.reserve"

PATH="$reserve_mutex_bin:$PATH" "$BETTER_RM" reserve-mutex.txt

mutex_suffixed=$(find "$TEST_TRASH_DIR" -type f \
    -name 'reserve-mutex.txt__20260724_120000_000000000__deadbeef*__*_*' 2>/dev/null |
    wc -l | tr -d ' ')
if [ ! -e reserve-mutex.txt ] && [ ! -f "$mutex_base_target" ] && [ "$mutex_suffixed" -eq 1 ]; then
    test_pass "保留鎖互斥使刪除改用 suffixed 目標，未佔用被保留的 base_target"
else
    test_fail "保留鎖互斥失效：寫入了被保留的 base_target 或未產生 suffixed 項目（suffixed=$mutex_suffixed）"
fi

# ============================================================================
# 測試 15: 受保護清單全覆蓋 (Test 15: every PROTECTED_DIRS entry)
# ============================================================================
test_title "測試 15: 受保護清單全覆蓋"

test_item "PROTECTED_DIRS 每一項都被 is_protected 認定為受保護"
# 先前只有 /、/home、/mnt* 與 .git 測得到，PROTECTED_DIRS 其餘 13 筆（含 $HOME）
# 可以整批從陣列刪掉而全套仍綠——better-rm 在 .bashrc 裡蓋掉 rm，那等於把
# `rm -rf ~` 變成把整個家目錄搬進垃圾桶並回傳成功。
# 這裡抽出 is_protected 與它的依賴單獨評估，不跑 main：拿真正的 /usr、/etc 去跑
# better-rm，保護一旦失效就是叫測試自己去搬整個檔案系統。清單刻意寫死，從
# PROTECTED_DIRS 讀回來會隨陣列一起縮小而永遠是綠的。抽函式的手法沿用
# test-hooks.js 對 install-hooks.sh 既有的做法。
# Only /, /home, /mnt* and .git were reachable before, so the other 13 entries of
# PROTECTED_DIRS -- $HOME included -- could be deleted wholesale with the suite
# green. better-rm is aliased over rm in .bashrc, so that turns `rm -rf ~` into a
# whole-home move that exits 0. is_protected and its dependencies are evaluated in
# isolation rather than through main: driving the real /usr or /etc through the
# binary would, the moment the guard failed, make the test itself move the whole
# filesystem. The 25+2 names are spelled out on purpose -- reading them back from
# PROTECTED_DIRS would shrink with the array and keep passing. The extraction idiom
# is the one test-hooks.js already uses on install-hooks.sh.
setup
cd "$TEST_WORK_DIR" || exit 1
protected_home="$TEST_WORK_DIR/protected-home"
mkdir -p "$protected_home"
# 0＝受保護、1＝未受保護、99＝抽取本身壞了（刻意與「未受保護」分開，壞掉的探針
# 不該被讀成發現）。
# Exit 0 protected, 1 unprotected, 99 the extraction itself broke -- kept distinct
# from "unprotected" so a broken probe cannot read as a finding.
is_protected_says_yes() {
    HOME="$2" bash -c '
        eval "$(sed -n "/^PROTECTED_DIRS=(/,/^)/p;/^PROTECTED_PATTERNS=(/,/^)/p" "$1")"
        eval "$(sed -n "/^normalize_path()/,/^}/p;/^is_protected()/,/^}/p" "$1")"
        if [ "$(type -t is_protected)" != function ] ||
           [ "${#PROTECTED_DIRS[@]}" -eq 0 ] ||
           [ "${#PROTECTED_PATTERNS[@]}" -eq 0 ]; then
            exit 99
        fi
        is_protected "$2"
    ' better-rm-is-protected "$BETTER_RM" "$1"
}
protected_unguarded=""
protected_probe_broken=""
for protected_path in / /Applications /Library /Network /System /System/Volumes \
                      /Users /Volumes \
                      /bin /boot /cores /dev /etc /home /lib /lib64 /mnt /opt \
                      /private /proc /root /sbin /sys /usr /var \
                      "$protected_home" "$protected_home/" \
                      "$protected_home/.claude" "$protected_home/.ssh"; do
    is_protected_says_yes "$protected_path" "$protected_home"
    case $? in
        0) ;;
        99) protected_probe_broken="$protected_probe_broken $protected_path" ;;
        *) protected_unguarded="$protected_unguarded $protected_path" ;;
    esac
done
# 負對照：這道探測不是「一律說是」，否則刪掉整個清單也會通過。
# 受保護的是那個目錄本身，不是它底下的一切：/Applications 是使用者可寫的，移除
# 單一 app bundle 是日常操作。清單一旦改成前綴比對，這裡的每一列都會轉紅——
# 那會是比原本的缺漏更嚴重的退化。
# Negative control: the probe is not simply saying yes to everything -- otherwise
# deleting the whole list would also pass. What is protected is the directory
# itself, not everything underneath it: /Applications is user-writable and
# removing a single app bundle is ordinary work. Every row below goes red if the
# comparison is ever widened to a prefix match, which would be a worse regression
# than the missing entries were.
protected_false_positive=""
# $HOME/.ssh/known_hosts.old 與 $HOME/.claude/projects/<session> 在這裡：受保護的是
# 那兩個目錄本身，裡面的東西照舊是日常工作（前者是 ssh 自己會留下的備份檔，後者是使
# 用者會定期清理的對話記錄）。$HOME/Library 也在這裡，而且是刻意的——它不在清單上，
# 清它底下的快取是例行工作；哪天有人把它加進 PROTECTED_DIRS，這一列會轉紅。
# $HOME/.ssh/known_hosts.old and $HOME/.claude/projects/<session> belong here: what is
# protected is those two directories themselves, while what is inside them stays
# ordinary work. $HOME/Library is here deliberately too -- it is NOT on the list,
# clearing caches under it is routine, and the day someone adds it this row goes red.
for unprotected_path in "$TEST_WORK_DIR/ordinary.txt" /mnt/c/project \
                        /usr/local/share/x "$protected_home/keep" \
                        "$protected_home/.ssh/known_hosts.old" \
                        "$protected_home/.claude/projects/session-dir" \
                        "$protected_home/.claude-backup" \
                        "$protected_home/Library" \
                        "$protected_home/Library/Caches/pip" \
                        /Applications/BetterRmProbe.app /Library/Preferences \
                        /Network/Servers /System/Library \
                        /Users/better-rm-probe /cores/core.1 \
                        /private/tmp/better-rm-probe; do
    if is_protected_says_yes "$unprotected_path" "$protected_home"; then
        protected_false_positive="$protected_false_positive $unprotected_path"
    fi
done
if [ -z "$protected_unguarded" ] && [ -z "$protected_false_positive" ] &&
   [ -z "$protected_probe_broken" ]; then
    test_pass "PROTECTED_DIRS 每一項都受保護，且一般路徑未被誤擋"
else
    test_fail "未受保護:${protected_unguarded:- 無}；誤擋:${protected_false_positive:- 無}；抽取失敗:${protected_probe_broken:- 無}"
fi

test_item "/Volumes 與 /mnt 的第一層掛載根受保護，掛載磁碟內的項目不受影響"
# /Volumes 是 macOS 的 /mnt：外接碟、Time Machine、網路共享都掛在它下面，移走
# /Volumes/<disk> 就是把整顆磁碟的掛載點帶走。保護必須停在掛載根，否則
# /Volumes/Backup/old.log 這種日常刪除也會被擋。
# 兩個根共用同一段程式，所以 /mnt 那幾列留在這裡：把那段改寫成只認 /Volumes 會讓
# /mnt 轉紅。這裡走 is_protected 探針而不跑 better-rm——/Volumes 在 macOS 上是真的，
# 保護一旦失效就是叫測試自己去搬真的掛載點。
# /Volumes is the macOS /mnt: external disks, Time Machine and network shares all
# mount under it, and removing /Volumes/<disk> takes the whole disk's mount point
# with it. The protection has to stop at the mount root, or an ordinary deletion
# inside a mounted disk is refused. Both roots share one block, so the /mnt rows
# stay here: a rewrite that only knows about /Volumes turns them red. Driven
# through the is_protected probe rather than better-rm because /Volumes really
# exists on macOS, and a failed guard would make the test move a real mount point.
mount_root_unguarded=""
mount_root_probe_broken=""
for mount_root_path in /Volumes /Volumes/BetterRmProbeDisk "/Volumes/Probe Disk" \
                       /Volumes/../Volumes/BetterRmProbeDisk \
                       /mnt /mnt/c /mnt/../mnt/wsl; do
    is_protected_says_yes "$mount_root_path" "$protected_home"
    case $? in
        0) ;;
        99) mount_root_probe_broken="$mount_root_probe_broken $mount_root_path" ;;
        *) mount_root_unguarded="$mount_root_unguarded $mount_root_path" ;;
    esac
done
mount_inside_blocked=""
for mount_inside_path in /Volumes/BetterRmProbeDisk/file.txt \
                         "/Volumes/Probe Disk/project/tmp" \
                         /mnt/c/project /mnt/c/project/tmp; do
    if is_protected_says_yes "$mount_inside_path" "$protected_home"; then
        mount_inside_blocked="$mount_inside_blocked $mount_inside_path"
    fi
done
if [ -z "$mount_root_unguarded" ] && [ -z "$mount_inside_blocked" ] &&
   [ -z "$mount_root_probe_broken" ]; then
    test_pass "/Volumes 與 /mnt 的掛載根受保護，掛載磁碟內的項目未被誤擋"
else
    test_fail "掛載根未受保護:${mount_root_unguarded:- 無}；掛載磁碟內誤擋:${mount_inside_blocked:- 無}；抽取失敗:${mount_root_probe_broken:- 無}"
fi

test_item "掛載根規則的兩種拼寫各自要能單獨擋下（解析後的、未解析的）"
# 掛載根那段迴圈對 real_path（解析過 symlink）與 norm_path（純字面正規化）各比對一次。
# 上一項的每一列都是「兩者剛好相同」的字面字串——不存在的路徑根本不會被解析，存在的
# 又解析回自己——所以把迴圈裡任何一個候選刪掉，整套仍然是綠的：實測兩種刪法各跑一次，
# 都沒有任何一列轉紅。這一項補上兩者會分岔的兩種形狀，讓每個候選各自成為必要條件。
#   解析後的那個：中途某一段是連結、指進真的掛載點。拿掉 real_path，
#   ~/disk -> /Volumes 這種捷徑底下的 disk/Backup 就變成可刪，而那就是整顆磁碟的掛載點。
#   用 PATH stub 造出「解析結果落在掛載根」，不靠一顆真的外接碟：/Volumes 在 Linux
#   runner 上不存在，拿真磁碟當條件只會讓這一列在 CI 永遠是綠的。stub 手法沿用下面
#   readlink 那一項既有的做法。
#   未解析的那個：字面正規化是純字串運算（normalize_path 不認 symlink），核心解析
#   `..` 卻是從連結指到的實體位置往上走。兩邊對同一個字串會得出不同答案，而使用者
#   打出來的那個拼寫讀起來就是一個掛載根——沒有連結介入時它就是真的掛載根，所以擋下
#   是 fail-closed 的那一邊。這一列不需要任何 stub，也不需要 /Volumes 真的存在。
# The mount-root loop compares real_path (symlink-resolved) and norm_path (purely
# lexical) separately. Every row in the item above is a literal string for which
# the two are identical -- a non-existent path is never resolved, an existing one
# resolves to itself -- so deleting either candidate from the loop left the suite
# green: measured, both deletions, not one row red. This item adds the two shapes
# where they diverge, so each candidate becomes load-bearing on its own.
#   The resolved one: an intermediate component is a link into a live mount. Drop
#   real_path and disk/Backup under a shortcut such as ~/disk -> /Volumes becomes
#   deletable, and that is a whole disk's mount point. A PATH stub produces the
#   "resolution lands on a mount root" property rather than a real external disk:
#   /Volumes does not exist on the Linux runner, so a real disk would leave this
#   row permanently green in CI. The stub idiom is the one the readlink item below
#   already uses.
#   The unresolved one: lexical normalisation is pure string work (normalize_path
#   knows nothing about symlinks) while the kernel walks `..` up from wherever the
#   link physically points. The two disagree about one string, and the spelling the
#   user typed reads as a mount root -- with no link in the way it IS the mount
#   root -- so refusing it is the fail-closed side. This row needs no stub and does
#   not need /Volumes to exist.
setup
cd "$TEST_WORK_DIR" || exit 1
dual_home="$TEST_WORK_DIR/dual-home"
mkdir -p "$dual_home"
dual_faults=""

# 解析後落在掛載根：stub 讓 readlink -f 成功回報 /Volumes/ProbeDisk。
# Resolved onto a mount root: the stub makes readlink -f succeed with /Volumes/ProbeDisk.
dual_root_bin="$TEST_WORK_DIR/dual-root-bin"
dual_inside_bin="$TEST_WORK_DIR/dual-inside-bin"
mkdir -p "$dual_root_bin" "$dual_inside_bin"
cat > "$dual_root_bin/readlink" <<'EOF'
#!/bin/sh
# 中途某一段是連結、指進掛載點時，解析結果就長這樣。
# What the resolution looks like when an intermediate component links into a mount.
printf '%s\n' "/Volumes/ProbeDisk"
exit 0
EOF
cat > "$dual_inside_bin/readlink" <<'EOF'
#!/bin/sh
# 同一支 stub，但解析到掛載磁碟「裡面」：這一列必須放行。
# The same stub resolving INSIDE the mounted disk: this row must be allowed.
printf '%s\n' "/Volumes/ProbeDisk/inside-item"
exit 0
EOF
chmod +x "$dual_root_bin/readlink" "$dual_inside_bin/readlink"
printf 'PROBE\n' > "$TEST_WORK_DIR/dual-probe.txt"
( PATH="$dual_root_bin:$PATH"; is_protected_says_yes "$TEST_WORK_DIR/dual-probe.txt" "$dual_home" )
case $? in
    0) ;;
    99) dual_faults="$dual_faults 探針壞掉（解析到掛載根）" ;;
    *) dual_faults="$dual_faults 解析後落在掛載根卻被放行" ;;
esac
( PATH="$dual_inside_bin:$PATH"; is_protected_says_yes "$TEST_WORK_DIR/dual-probe.txt" "$dual_home" )
case $? in
    0) dual_faults="$dual_faults 解析到掛載磁碟內卻被誤擋" ;;
    99) dual_faults="$dual_faults 探針壞掉（解析到磁碟內）" ;;
esac

# 字面正規化落在掛載根：`..` 的個數剛好把 $TEST_WORK_DIR 的每一層都消掉，字面上就是
# /Volumes/ProbeDisk；核心卻是從連結指到的深層目錄往上走，實際落在 sandbox 裡。
# 深度由 $TEST_WORK_DIR 算出來，不是寫死的，換一個工作目錄這一列仍然成立。
# Lexically onto a mount root: the `..` count cancels every component of
# $TEST_WORK_DIR, so the string reads as /Volumes/ProbeDisk, while the kernel walks
# up from where the link physically points and lands back inside the sandbox. The
# depth is derived from $TEST_WORK_DIR rather than hard-coded, so the row survives
# a different working directory.
dual_rest="${TEST_WORK_DIR#/}"
dual_depth=0
while [ -n "$dual_rest" ]; do
    dual_depth=$((dual_depth + 1))
    dual_next="${dual_rest#*/}"
    if [ "$dual_next" = "$dual_rest" ]; then
        dual_rest=""
    else
        dual_rest="$dual_next"
    fi
done
dual_deep="$TEST_WORK_DIR"
dual_dots=""
dual_i=0
# 連結自身那一層 + $TEST_WORK_DIR 的層數：實體深度與 .. 個數必須相等，往上走才會剛好
# 回到 $TEST_WORK_DIR。
# The link's own component plus $TEST_WORK_DIR's depth: the physical depth and the
# number of `..` have to match for the walk to land back on $TEST_WORK_DIR.
while [ "$dual_i" -le "$dual_depth" ]; do
    dual_deep="$dual_deep/d"
    dual_dots="$dual_dots/.."
    dual_i=$((dual_i + 1))
done
mkdir -p "$dual_deep" "$TEST_WORK_DIR/Volumes/ProbeDisk/inside-item"
ln -s "$dual_deep" "$TEST_WORK_DIR/dual-deeplink"
dual_lexical="$TEST_WORK_DIR/dual-deeplink$dual_dots/Volumes/ProbeDisk"
# 前提條件：這條路徑真的存在、自己不是連結（否則 is_protected 根本不會去解析它），
# 而且解析後確實落在 sandbox 裡而不是 /Volumes。前提不成立就直接記成錯誤，不能讓
# 這一列變成一個什麼都沒驗到的綠燈。
# Preconditions: the path really exists, is not itself a link (or is_protected would
# never resolve it), and really does resolve inside the sandbox rather than to
# /Volumes. A broken precondition is recorded as a fault rather than left to turn
# this row into a green that checked nothing.
if [ -L "$dual_lexical" ] || [ ! -e "$dual_lexical" ] ||
   [ "$(readlink -f "$dual_lexical")" != "$(cd "$TEST_WORK_DIR" && pwd -P)/Volumes/ProbeDisk" ]; then
    dual_faults="$dual_faults 字面拼寫那一列的前提不成立"
fi
is_protected_says_yes "$dual_lexical" "$dual_home"
case $? in
    0) ;;
    99) dual_faults="$dual_faults 探針壞掉（字面掛載根）" ;;
    *) dual_faults="$dual_faults 字面拼寫是掛載根卻被放行" ;;
esac
if is_protected_says_yes "$dual_lexical/inside-item" "$dual_home"; then
    dual_faults="$dual_faults 字面拼寫在掛載磁碟內卻被誤擋"
fi
if [ -z "$dual_faults" ]; then
    test_pass "掛載根規則的兩種拼寫各自都擋得下，且掛載磁碟內的項目仍被放行"
else
    test_fail "掛載根規則的雙拼寫比對有缺口:$dual_faults"
fi

test_item "macOS firmlink 拼寫（/System/Volumes/Data/…）與根拼寫是同一個物件"
# 實測 stat -f '%d:%i'：/Users/sieg 與 /System/Volumes/Data/Users/sieg 是同一個
# device、同一個 inode；/Applications 與 /System/Volumes/Data/Applications 也是。
# firmlink 不是 symlink，readlink -f 兩個方向都把路徑原樣送回來，所以沒有任何
# 正規化會讓這兩種拼寫碰面——$HOME 的保護從第一天起就有這個洞：整個家目錄可以
# 用 Data 卷宗的拼寫搬走，而清單一列都沒攔到。/System/Volumes 本身則是現代 Mac
# 掛載自己每一顆 APFS 卷宗的地方，卻不在 /mnt、/Volumes 那個掛載根迴圈裡。
# 判準刻意不是「路徑存在」：不存在的 /System/Volumes/Data/Users/<名字> 一樣要擋，
# 否則家目錄還沒建立、或在另一台機器上，同一條命令就穿過去了。
# 這裡走 is_protected 探針而不跑 better-rm——這些路徑在 macOS 上是真的。
# Measured with stat -f '%d:%i': /Users/sieg and /System/Volumes/Data/Users/sieg are
# the same device and the same inode, and so are /Applications and
# /System/Volumes/Data/Applications. A firmlink is not a symlink -- readlink -f
# hands either spelling straight back -- so no canonicalisation ever brings the two
# together, and the $HOME protection has had this hole from the start: the whole
# home directory is removable under the Data-volume spelling with no list entry
# stopping it. /System/Volumes is also where every modern Mac mounts its own APFS
# volumes, and it was not in the /mnt, /Volumes mount-parent loop. The criterion is
# deliberately not "the path exists": a non-existent /System/Volumes/Data/Users/<name>
# has to be refused too, or the same command walks through on a machine where the
# home directory has not been created yet. Driven through the is_protected probe
# rather than better-rm because these paths are real on macOS.
firmlink_home="/Users/better-rm-probe-home"
firmlink_unguarded=""
firmlink_probe_broken=""
for firmlink_path in /System/Volumes /System/Volumes/Data /System/Volumes/Preboot \
                     /System/Volumes/Data/Users /System/Volumes/Data/Applications \
                     /System/Volumes/Data/private /System/Volumes/Data/etc \
                     "/System/Volumes/Data$firmlink_home"; do
    is_protected_says_yes "$firmlink_path" "$firmlink_home"
    case $? in
        0) ;;
        99) firmlink_probe_broken="$firmlink_probe_broken $firmlink_path" ;;
        *) firmlink_unguarded="$firmlink_unguarded $firmlink_path" ;;
    esac
done
# 負對照：認得這個拼寫不等於把 Data 卷宗底下的一切都變成刪不掉的。對應關係是逐條
# 比對清單，不是前綴——家目錄底下的檔案、別人的家目錄、掛載根再下一層都照舊可刪。
# Negative control: recognising the spelling must not turn everything under the
# Data volume into an undeletable path. The mapping feeds the same exact-match
# list, not a prefix: files inside the home directory, somebody else's home
# directory, and anything below a mount root all stay deletable.
firmlink_false_positive=""
for firmlink_inside in "/System/Volumes/Data$firmlink_home/keep" \
                       /System/Volumes/Data/Users/better-rm-other \
                       /System/Volumes/Data/Applications/BetterRmProbe.app \
                       /System/Volumes/Data/private/tmp/better-rm-probe \
                       /System/Volumes/DataDrive/file.txt; do
    if is_protected_says_yes "$firmlink_inside" "$firmlink_home"; then
        firmlink_false_positive="$firmlink_false_positive $firmlink_inside"
    fi
done
if [ -z "$firmlink_unguarded" ] && [ -z "$firmlink_false_positive" ] &&
   [ -z "$firmlink_probe_broken" ]; then
    test_pass "firmlink 拼寫與 /System/Volumes 掛載根受保護，Data 卷宗內的項目未被誤擋"
else
    test_fail "firmlink 拼寫未受保護:${firmlink_unguarded:- 無}；誤擋:${firmlink_false_positive:- 無}；抽取失敗:${firmlink_probe_broken:- 無}"
fi

test_item "firmlink 改寫的兩條路徑（已解析與字面）各自都必須生效"
# is_protected 把 firmlink 前綴改寫兩次：一次在 real_path（symlink 解析後）、一次在
# norm_path（純字面）。上面那一項的每一列都是字面字串，兩者恆等——不存在的路徑不會被
# 解析，存在的路徑解析回自己——所以刪掉任一半，整套仍然全綠。實測：兩個單邊突變各自
# 都是 120/120 通過，只有兩邊一起刪才紅。這一項補上兩者會分歧的形狀，讓每一半各自
# 都是承重的。
#   已解析那一列：中途某一段連結指進 Data 卷宗時，解析結果就帶著 firmlink 前綴，而
#   使用者打出來的字面拼寫完全看不出來。用 PATH stub 造出這個性質，不靠真的
#   /System/Volumes/Data：Linux runner 上它不存在，拿真路徑當條件只會讓這一列在 CI
#   永遠是綠的。stub 手法沿用上面掛載根與 readlink 那兩項既有的做法。
#   字面那一列：`..` 的個數剛好把 $TEST_WORK_DIR 每一層都消掉，字面正規化的結果就是
#   /System/Volumes/Data/Users；核心卻是從連結指到的深層目錄往上走，實際落在 sandbox
#   裡，所以 real_path 完全不帶前綴。使用者打出來的拼寫讀起來就是家目錄那一卷，沒有
#   連結介入時它就是真的家目錄——擋下是 fail-closed 的那一邊。這一列不需要 stub，也
#   不需要 /System/Volumes/Data 真的存在，兩個平台上跑的是同一件事。
# is_protected rewrites the firmlink prefix twice: once on real_path (after symlink
# resolution) and once on norm_path (purely lexical). Every row in the item above is
# a literal string for which the two are identical -- a non-existent path is never
# resolved, an existing one resolves to itself -- so deleting either half left the
# suite green: measured, each single-sided mutation passed 120/120, and only
# deleting both went red. This item adds the two shapes where they diverge, so each
# half becomes load-bearing on its own.
#   The resolved one: when an intermediate component links into the data volume the
#   resolution carries the firmlink prefix while the spelling the user typed shows
#   no sign of it. A PATH stub produces that property rather than a real
#   /System/Volumes/Data: it does not exist on the Linux runner, so a real path
#   would leave this row permanently green in CI. The stub idiom is the one the
#   mount-root and readlink items above already use.
#   The lexical one: the `..` count cancels every component of $TEST_WORK_DIR, so
#   lexical normalisation lands on /System/Volumes/Data/Users, while the kernel
#   walks up from where the link physically points and stays inside the sandbox --
#   real_path never carries the prefix at all. The spelling the user typed reads as
#   the home volume, and with no link in the way it IS the home volume, so refusing
#   it is the fail-closed side. This row needs no stub and does not need
#   /System/Volumes/Data to exist; both platforms run the same thing.
setup
cd "$TEST_WORK_DIR" || exit 1
fldual_home="$TEST_WORK_DIR/firmlink-dual-home"
mkdir -p "$fldual_home"
fldual_faults=""

# 解析後帶著 firmlink 前綴：stub 讓 readlink -f 成功回報 /System/Volumes/Data/Users。
# Resolved onto the firmlink spelling: the stub makes readlink -f succeed with
# /System/Volumes/Data/Users.
fldual_root_bin="$TEST_WORK_DIR/firmlink-root-bin"
fldual_inside_bin="$TEST_WORK_DIR/firmlink-inside-bin"
mkdir -p "$fldual_root_bin" "$fldual_inside_bin"
cat > "$fldual_root_bin/readlink" <<'EOF'
#!/bin/sh
# 中途某一段是連結、指進 Data 卷宗時，解析結果就長這樣。
# What the resolution looks like when an intermediate component links into the data volume.
printf '%s\n' "/System/Volumes/Data/Users"
exit 0
EOF
cat > "$fldual_inside_bin/readlink" <<'EOF'
#!/bin/sh
# 同一支 stub，但解析到對應目錄「裡面」：這一列必須放行。
# The same stub resolving INSIDE the mapped directory: this row must be allowed.
printf '%s\n' "/System/Volumes/Data/Users/someone/project"
exit 0
EOF
chmod +x "$fldual_root_bin/readlink" "$fldual_inside_bin/readlink"
printf 'PROBE\n' > "$TEST_WORK_DIR/firmlink-dual-probe.txt"
# 前提條件：探針自己的字面拼寫不能帶著前綴，否則這一列會被 norm_path 那一半蓋過去，
# 變成一個什麼都沒驗到的綠燈。探針刻意是一般檔案而不是連結：引數自己是連結時
# is_protected 依自身路徑判定，根本不會去解析。
# Precondition: the probe's own lexical spelling must not carry the prefix, or the
# norm_path half would cover this row and it would prove nothing. The probe is
# deliberately a regular file, not a link: an argument that is itself a link is
# judged by its own path and never resolved.
case "$TEST_WORK_DIR/firmlink-dual-probe.txt" in
    /System/Volumes/Data/*) fldual_faults="$fldual_faults 已解析那一列的前提不成立" ;;
esac
( PATH="$fldual_root_bin:$PATH"; is_protected_says_yes "$TEST_WORK_DIR/firmlink-dual-probe.txt" "$fldual_home" )
case $? in
    0) ;;
    99) fldual_faults="$fldual_faults 探針壞掉（解析後帶前綴）" ;;
    *) fldual_faults="$fldual_faults 解析後落在 firmlink 拼寫卻被放行" ;;
esac
( PATH="$fldual_inside_bin:$PATH"; is_protected_says_yes "$TEST_WORK_DIR/firmlink-dual-probe.txt" "$fldual_home" )
case $? in
    0) fldual_faults="$fldual_faults 解析到對應目錄內卻被誤擋" ;;
    99) fldual_faults="$fldual_faults 探針壞掉（解析到目錄內）" ;;
esac

# 字面正規化落在 firmlink 拼寫：深度由 $TEST_WORK_DIR 算出來，不是寫死的。
# Lexically onto the firmlink spelling: the depth is derived from $TEST_WORK_DIR
# rather than hard-coded.
fldual_rest="${TEST_WORK_DIR#/}"
fldual_depth=0
while [ -n "$fldual_rest" ]; do
    fldual_depth=$((fldual_depth + 1))
    fldual_next="${fldual_rest#*/}"
    if [ "$fldual_next" = "$fldual_rest" ]; then
        fldual_rest=""
    else
        fldual_rest="$fldual_next"
    fi
done
fldual_deep="$TEST_WORK_DIR"
fldual_dots=""
fldual_i=0
# 連結自身那一層 + $TEST_WORK_DIR 的層數：實體深度與 .. 個數必須相等，往上走才會剛好
# 回到 $TEST_WORK_DIR。
# The link's own component plus $TEST_WORK_DIR's depth: the physical depth and the
# number of `..` have to match for the walk to land back on $TEST_WORK_DIR.
while [ "$fldual_i" -le "$fldual_depth" ]; do
    fldual_deep="$fldual_deep/d"
    fldual_dots="$fldual_dots/.."
    fldual_i=$((fldual_i + 1))
done
mkdir -p "$fldual_deep" "$TEST_WORK_DIR/System/Volumes/Data/Users/inside-item"
ln -s "$fldual_deep" "$TEST_WORK_DIR/firmlink-deeplink"
fldual_lexical="$TEST_WORK_DIR/firmlink-deeplink$fldual_dots/System/Volumes/Data/Users"
# 前提條件：這條路徑真的存在、自己不是連結（否則 is_protected 不會去解析它），而且
# 解析後確實落在 sandbox 裡而不是真的 /System/Volumes/Data——解析結果一旦帶著前綴，
# 這一列就會被 real_path 那一半蓋過去。前提不成立就記成錯誤。
# Preconditions: the path really exists, is not itself a link (or is_protected would
# never resolve it), and really does resolve inside the sandbox rather than to the
# real /System/Volumes/Data -- a resolution carrying the prefix would let the
# real_path half cover this row. A broken precondition is recorded as a fault.
fldual_physical="$(cd "$TEST_WORK_DIR" && pwd -P)/System/Volumes/Data/Users"
if [ -L "$fldual_lexical" ] || [ ! -e "$fldual_lexical" ] ||
   [ "$(readlink -f "$fldual_lexical")" != "$fldual_physical" ]; then
    fldual_faults="$fldual_faults 字面拼寫那一列的前提不成立"
fi
is_protected_says_yes "$fldual_lexical" "$fldual_home"
case $? in
    0) ;;
    99) fldual_faults="$fldual_faults 探針壞掉（字面 firmlink 拼寫）" ;;
    *) fldual_faults="$fldual_faults 字面拼寫是 firmlink 拼寫卻被放行" ;;
esac
if is_protected_says_yes "$fldual_lexical/inside-item" "$fldual_home"; then
    fldual_faults="$fldual_faults 字面拼寫在對應目錄內卻被誤擋"
fi
if [ -z "$fldual_faults" ]; then
    test_pass "firmlink 改寫在已解析與字面兩條路徑上各自生效，對應目錄內的項目仍被放行"
else
    test_fail "firmlink 改寫的雙路徑比對有缺口:$fldual_faults"
fi

test_item ".git 內部的路徑與 .git 本身一樣受保護"
# PROTECTED_PATTERNS 只認「路徑結束在 .git」，所以 .git/objects、.git/refs、
# .git/index.lock 全部是普通的刪除目標——`rm -rf .git/objects` 會把整個物件庫搬進
# 垃圾桶並回傳成功，倉庫當場毀掉。agent 路徑上的那道 hook 從一開始就拒絕任何含有
# .git 元件的路徑，兩道守衛因此對同一條路徑給出相反的答案；這裡把 better-rm 對齊到
# 嚴格的那一邊：擋過頭只是不方便，擋不夠丟的是資料。
# 這是刻意的收緊，也確實會擋掉一件正當的事：git 中斷後手動清 .git/index.lock。
# 使用者要嘛用 /bin/rm 繞過（見 README 那一節），要嘛由維護者另外裁決是否開豁免。
# PROTECTED_PATTERNS matched only a path that ENDS at .git, so .git/objects,
# .git/refs and .git/index.lock were ordinary deletion targets: `rm -rf .git/objects`
# moved the whole object store to the trash and exited 0, which destroys the
# repository. The agent-path hook has always refused any path with a .git COMPONENT,
# so the two guards answered the same path differently. better-rm is aligned onto
# the stricter side: too strict costs an inconvenience, too loose costs data.
# The friction is real and intended: clearing a stale .git/index.lock by hand after
# an interrupted git operation is now refused too. Documented in the README next to
# the .git entry; whether to carve out an exemption is the maintainer's call.
setup
cd "$TEST_WORK_DIR" || exit 1
gitinside_home="$TEST_WORK_DIR/gitinside-home"
mkdir -p "$gitinside_home"
gitinside_unguarded=""
gitinside_probe_broken=""
# 相對拼寫那一列走的是 is_protected 自己的 $(pwd) 前置，與絕對拼寫不同的碼路徑。
# The relative row exercises is_protected's own $(pwd) prefixing, a different code
# path from the absolute ones.
for gitinside_path in "$TEST_WORK_DIR/repo/.git/index.lock" \
                      "$TEST_WORK_DIR/repo/.git/objects" \
                      "$TEST_WORK_DIR/repo/.git/objects/pack" \
                      "$TEST_WORK_DIR/repo/sub/.git/refs/heads" \
                      ".git/objects/pack"; do
    is_protected_says_yes "$gitinside_path" "$gitinside_home"
    case $? in
        0) ;;
        99) gitinside_probe_broken="$gitinside_probe_broken $gitinside_path" ;;
        *) gitinside_unguarded="$gitinside_unguarded $gitinside_path" ;;
    esac
done
# 負對照：.git 必須是完整的路徑元件，不是子字串。規則一旦寫成「路徑裡有 .git」，
# .gitignore、.github/workflows、vendor.git/objects 這些日常操作都會被擋掉——那會
# 比原本的缺漏更糟。
# Negative control: .git has to be a whole path COMPONENT, not a substring. A rule
# written as "the path contains .git" would refuse .gitignore, .github/workflows and
# vendor.git/objects -- ordinary work, and a worse regression than the gap was.
gitinside_false_positive=""
for gitinside_ok in "$TEST_WORK_DIR/repo/.gitignore" \
                    "$TEST_WORK_DIR/repo/.github/workflows" \
                    "$TEST_WORK_DIR/repo/vendor.git/objects" \
                    "$TEST_WORK_DIR/repo/.git.bak/objects" \
                    "$TEST_WORK_DIR/repo/docs/git/objects"; do
    if is_protected_says_yes "$gitinside_ok" "$gitinside_home"; then
        gitinside_false_positive="$gitinside_false_positive $gitinside_ok"
    fi
done
if [ -z "$gitinside_unguarded" ] && [ -z "$gitinside_false_positive" ] &&
   [ -z "$gitinside_probe_broken" ]; then
    test_pass ".git 內部的路徑受保護，.gitignore／.github／vendor.git 未被誤擋"
else
    test_fail ".git 內部未受保護:${gitinside_unguarded:- 無}；誤擋:${gitinside_false_positive:- 無}；抽取失敗:${gitinside_probe_broken:- 無}"
fi

test_item ".git 內部的路徑真的攔在 move_to_trash 前面（端到端）"
# 上一項證明判斷改了，這一項證明那個判斷擋在真正的搬移之前：檔案必須還在原地。
# The previous item proves the judgement changed; this one proves it gates the real
# move: the file has to still be there afterwards.
setup
cd "$TEST_WORK_DIR" || exit 1
mkdir -p repo/.git/objects
printf 'OBJECTS\n' > repo/.git/objects/keep.pack
printf 'LOCK\n' > repo/.git/index.lock
gitinside_e2e=$("$BETTER_RM" -rf repo/.git/objects repo/.git/index.lock 2>&1)
if printf '%s' "$gitinside_e2e" | grep -q "拒絕刪除受保護的目錄" &&
   [ -f repo/.git/objects/keep.pack ] && [ -f repo/.git/index.lock ]; then
    test_pass ".git 內部的刪除被拒絕，物件庫與 index.lock 都還在"
else
    test_fail ".git 內部的刪除未被拒絕（objects=$([ -f repo/.git/objects/keep.pack ] && echo yes || echo no)；lock=$([ -f repo/.git/index.lock ] && echo yes || echo no)；訊息=${gitinside_e2e}）"
fi

test_item "BETTER_RM_PROTECTED_DIRS 宣告的目錄受保護"
# 這個環境變數是使用者自己加保護的唯一介面，agent 路徑上的 hook 讀它（
# hooks/protect-important-paths.js 的 evaluate），better-rm 全檔一處都沒提到它。
# 於是同一個變數在 agent 路徑上生效、在它本來要保護的 rm 替身上完全沒作用——使用者
# 設了它、看見 agent 被擋，就會以為自己受保護了。
# 解析必須與 hook 完全一致，否則兩邊各保護各的：以 ':' 分隔（Node 的 path.delimiter
# 在這兩個平台就是它）、空項略過、相對項以 cwd 為基準解析。空項尤其要緊：不略過的
# 話 "" 會解析成當前目錄，於是一個結尾冒號就讓使用者的工作目錄變成刪不掉的。
# This variable is the only way a user can add protection of their own. The
# agent-path hook reads it (evaluate() in hooks/protect-important-paths.js);
# better-rm did not mention it anywhere in the file, so the same variable hardened
# the agent path and did nothing for the rm replacement it exists to configure --
# a user who sets it and watches the agent get refused believes they are covered.
# The parsing has to match the hook's exactly: ':' separated (that is Node's
# path.delimiter on both platforms), empty entries skipped, relative entries
# resolved against the working directory. The empty entry matters most: keeping it
# resolves "" to the current directory, so one trailing colon would make the user's
# own working directory undeletable.
setup
cd "$TEST_WORK_DIR" || exit 1
extradirs_home="$TEST_WORK_DIR/extradirs-home"
mkdir -p "$extradirs_home"
# 絕對項、空項、相對項各一，一次把三種解析都放進同一個值裡。
# One absolute, one empty and one relative entry, so all three parses are exercised
# by the same value.
extradirs_value="$TEST_WORK_DIR/secrets::relative-secrets"
extradirs_says_yes() {
    HOME="$3" BETTER_RM_PROTECTED_DIRS="$2" bash -c '
        eval "$(sed -n "/^PROTECTED_DIRS=(/,/^)/p;/^PROTECTED_PATTERNS=(/,/^)/p" "$1")"
        eval "$(sed -n "/^normalize_path()/,/^}/p;/^is_protected()/,/^}/p" "$1")"
        if [ "$(type -t is_protected)" != function ] ||
           [ "${#PROTECTED_DIRS[@]}" -eq 0 ] ||
           [ "${#PROTECTED_PATTERNS[@]}" -eq 0 ]; then
            exit 99
        fi
        is_protected "$2"
    ' better-rm-is-protected "$BETTER_RM" "$1"
}
extradirs_unguarded=""
extradirs_probe_broken=""
for extradirs_path in "$TEST_WORK_DIR/secrets" "$TEST_WORK_DIR/secrets/" \
                      "$TEST_WORK_DIR/relative-secrets" "relative-secrets"; do
    extradirs_says_yes "$extradirs_path" "$extradirs_value" "$extradirs_home"
    case $? in
        0) ;;
        99) extradirs_probe_broken="$extradirs_probe_broken $extradirs_path" ;;
        *) extradirs_unguarded="$extradirs_unguarded $extradirs_path" ;;
    esac
done
# 負對照：保護的是宣告的那個目錄本身，不是它底下的一切，也不是沒宣告的東西；
# 而工作目錄本身必須照舊可刪，否則就是空項被當成了 "."。
# Negative control: what is protected is the declared directory itself -- not what
# is inside it, not what was never declared -- and the working directory must stay
# removable, or the empty entry was read as ".".
extradirs_false_positive=""
for extradirs_ok in "$TEST_WORK_DIR/secrets/inside-item" "$TEST_WORK_DIR/not-secrets" \
                    "$TEST_WORK_DIR/relative-secrets/inside-item" "$TEST_WORK_DIR"; do
    if extradirs_says_yes "$extradirs_ok" "$extradirs_value" "$extradirs_home"; then
        extradirs_false_positive="$extradirs_false_positive $extradirs_ok"
    fi
done
# 反恆真：變數沒設的時候，同一條路徑必須是可刪的，否則上面每一列都可能是別的規則
# 擋下來的。
# Anti-tautology: with the variable unset the same path must be removable, or the
# rows above could be passing because of some other rule entirely.
if extradirs_says_yes "$TEST_WORK_DIR/secrets" "" "$extradirs_home"; then
    extradirs_false_positive="$extradirs_false_positive unset:$TEST_WORK_DIR/secrets"
fi
if [ -z "$extradirs_unguarded" ] && [ -z "$extradirs_false_positive" ] &&
   [ -z "$extradirs_probe_broken" ]; then
    test_pass "BETTER_RM_PROTECTED_DIRS 的絕對／相對項受保護，空項與其內容未被誤擋"
else
    test_fail "宣告的目錄未受保護:${extradirs_unguarded:- 無}；誤擋:${extradirs_false_positive:- 無}；抽取失敗:${extradirs_probe_broken:- 無}"
fi

test_item "BETTER_RM_PROTECTED_DIRS 真的攔在 move_to_trash 前面（端到端）"
# 上一項證明判斷認得這個變數，這一項證明那個判斷擋在真正的搬移之前。
# The previous item proves the judgement reads the variable; this one proves it
# gates the real move.
setup
cd "$TEST_WORK_DIR" || exit 1
mkdir -p secrets
printf 'SECRET\n' > secrets/keep.txt
extradirs_e2e=$(BETTER_RM_PROTECTED_DIRS="$TEST_WORK_DIR/secrets" "$BETTER_RM" -rf secrets 2>&1)
extradirs_e2e_allowed=0
BETTER_RM_PROTECTED_DIRS="$TEST_WORK_DIR/secrets" "$BETTER_RM" -rf secrets/keep.txt >/dev/null 2>&1 ||
    extradirs_e2e_allowed=$?
if printf '%s' "$extradirs_e2e" | grep -q "拒絕刪除受保護的目錄" &&
   [ -d secrets ] && [ "$extradirs_e2e_allowed" -eq 0 ] && [ ! -e secrets/keep.txt ]; then
    test_pass "宣告的目錄被拒絕，目錄內的檔案仍可刪除"
else
    test_fail "宣告的目錄未被保護或內容被誤擋（目錄存在=$([ -d secrets ] && echo yes || echo no)；刪內容 exit=${extradirs_e2e_allowed}；訊息=${extradirs_e2e}）"
fi

test_item "宣告的項目本身是連結時，指到同一個物件的第二種拼寫仍受保護"
# 引數自己是連結時 is_protected 不解析（刪連結碰不到 target），於是只剩「拼寫」在判
# 它——但拼寫是字串，清單上的項目是一個物件。這台 Mac 上 /etc、/var、/home 都是連結：
# /ETC 與 /etc 是同一條連結（實測同 dev:ino），卻只有小寫那種寫法被擋下來，而是真目錄
# 的項目在 readlink -f 之後全都折對了。這裡用「別名父目錄」而不是大小寫造出第二種拼
# 寫，所以這一項在分大小寫的檔案系統上測到的是同一件事。
# A symlink argument is not resolved (deleting a link cannot touch its target), so
# the only thing left judging it is its spelling -- and a spelling is a string
# while a list entry is an OBJECT. On this Mac /etc, /var and /home are symlinks:
# /ETC names the same link as /etc (measured: one dev:ino) and only the lower-case
# spelling was refused, while every entry that is a real directory folded once
# readlink -f had run. The second spelling here is made with an aliased parent
# rather than a case fold, so the row means the same thing on a case-sensitive
# filesystem.
setup
cd "$TEST_WORK_DIR" || exit 1
identity_home="$TEST_WORK_DIR/identity-home"
mkdir -p "$identity_home" identity/actual
ln -s "$TEST_WORK_DIR/identity/actual" "$TEST_WORK_DIR/identity/declared-link"
ln -s "$TEST_WORK_DIR/identity/actual" "$TEST_WORK_DIR/identity/other-link"
ln -s "$TEST_WORK_DIR/identity" "$TEST_WORK_DIR/identity-alias"
identity_declared="$TEST_WORK_DIR/identity/declared-link"
identity_unguarded=""
identity_false_positive=""
identity_probe_broken=""
extradirs_says_yes "$TEST_WORK_DIR/identity-alias/declared-link" "$identity_declared" "$identity_home"
case $? in
    0) ;;
    99) identity_probe_broken="$identity_probe_broken alias-spelling" ;;
    *) identity_unguarded="$identity_unguarded $TEST_WORK_DIR/identity-alias/declared-link" ;;
esac
# 反恆真：規則要說的是「這個引數就是清單上那一項」，不是「凡是連結一律拒絕」，也不是
# 「凡經別名碰到的一律拒絕」。三個對照全部是同樣方式碰到的路徑。
# Anti-tautology: the rule must say "this argument IS that entry", not "every
# symlink is refused" and not "anything reached through the alias is refused".
for identity_ordinary in "$TEST_WORK_DIR/identity/other-link" \
                         "$TEST_WORK_DIR/identity-alias/other-link" \
                         "$TEST_WORK_DIR/identity/actual"; do
    extradirs_says_yes "$identity_ordinary" "$identity_declared" "$identity_home"
    case $? in
        0) identity_false_positive="$identity_false_positive $identity_ordinary" ;;
        99) identity_probe_broken="$identity_probe_broken $identity_ordinary" ;;
        *) ;;
    esac
done
if [ -z "$identity_unguarded" ] && [ -z "$identity_false_positive" ] &&
   [ -z "$identity_probe_broken" ]; then
    test_pass "同一條連結的第二種拼寫受保護，其他連結與 target 未被誤擋"
else
    test_fail "第二種拼寫未受保護:${identity_unguarded:- 無}；誤擋:${identity_false_positive:- 無}；抽取失敗:${identity_probe_broken:- 無}"
fi

test_item "同一條連結的第二種拼寫真的攔在 move_to_trash 前面（端到端）"
# 上一項證明判斷認得那個物件，這一項證明那個判斷擋在真正的搬移之前。
# The previous item proves the judgement recognises the object; this one proves it
# gates the real move.
identity_e2e=$(BETTER_RM_PROTECTED_DIRS="$identity_declared" \
    "$BETTER_RM" -rf "$TEST_WORK_DIR/identity-alias/declared-link" 2>&1)
identity_other_allowed=0
BETTER_RM_PROTECTED_DIRS="$identity_declared" \
    "$BETTER_RM" -rf "$TEST_WORK_DIR/identity-alias/other-link" >/dev/null 2>&1 ||
    identity_other_allowed=$?
if printf '%s' "$identity_e2e" | grep -q "拒絕刪除受保護的目錄" &&
   [ -L "$identity_declared" ] && [ "$identity_other_allowed" -eq 0 ] &&
   [ ! -L "$TEST_WORK_DIR/identity/other-link" ]; then
    test_pass "第二種拼寫被拒絕，宣告的連結還在，其他連結仍可刪除"
else
    test_fail "第二種拼寫未被保護或誤擋（連結存在=$([ -L "$identity_declared" ] && echo yes || echo no)；刪其他連結 exit=${identity_other_allowed}；訊息=${identity_e2e}）"
fi

test_item "清單上的 macOS 實體路徑項目由這一套自己釘住"
# 這幾項原本只被「兩份清單互相比對」的漂移守衛釘住：把 /private/etc 從 better-rm 的
# PROTECTED_DIRS 拿掉，這一套 126 個測試照樣全綠（實測）。漂移守衛住在 hook 那一套裡，
# 它證明的是「兩邊一致」，不是「這一項存在」——兩份一起拿掉它就什麼都不說了。
# These entries were pinned only by the cross-list drift guard: removing
# /private/etc from better-rm's PROTECTED_DIRS left this 126-test suite green
# (measured). That guard lives in the hook suite and proves the two lists AGREE,
# not that any particular entry exists; remove it from both and it says nothing.
setup
cd "$TEST_WORK_DIR" || exit 1
physical_home="$TEST_WORK_DIR/physical-home"
mkdir -p "$physical_home"
physical_missing=""
physical_false_positive=""
for physical_path in /private/etc /private/var /etc /var; do
    if ! extradirs_says_yes "$physical_path" "" "$physical_home"; then
        physical_missing="$physical_missing $physical_path"
    fi
done
# 負對照：保護的是那個目錄本身，不是它的內容；/private/tmp 刻意不在清單上。
# Negative control: the directory itself, not its contents; /private/tmp is
# deliberately absent because scratch work lives there.
for physical_ordinary in /private/etc/some-config /private/var/folders /private/tmp; do
    if extradirs_says_yes "$physical_ordinary" "" "$physical_home"; then
        physical_false_positive="$physical_false_positive $physical_ordinary"
    fi
done
if [ -z "$physical_missing" ] && [ -z "$physical_false_positive" ]; then
    test_pass "/private/etc 與 /private/var 受保護，其內容與 /private/tmp 未被誤擋"
else
    test_fail "未受保護:${physical_missing:- 無}；誤擋:${physical_false_positive:- 無}"
fi

test_item "身分比對必須帶著 device 那一半，不能只比 inode"
# inode 只在同一個 device 內唯一。少了 dev 這一半，第二顆卷宗上編號恰好相同的連結會被
# 無條件拒絕。「不同 device、相同 inode」的兩個物件造不出來（inode 編號不是我們能指定
# 的），所以改用 stat shim 驅動——與這支套件既有的 make_xdev_stat_shim 同一招。
# shim 會把「借方」那條路徑改成問「出借方」，再把 device 加一；因此它會照著 better-rm
# 當下要求的格式回答：格式若被改成只有 %i，shim 就沒有 device 可加，兩邊變成相等而被
# 拒絕——這正是這一項要抓的退化。
# An inode identifies an object only within a device. Dropping the device half
# refuses a link on a second volume that happens to be numbered like a declared
# entry. Two objects with equal inode numbers on different devices cannot be made
# to order, so this runs through a stat shim, the same technique
# make_xdev_stat_shim already uses here. The shim answers for the BORROWER by
# asking about the LENDER and bumping the device, and it honours whatever format
# better-rm asked for -- so a format reduced to just %i has no device to bump, the
# two sides become equal, and the refusal this test forbids appears.
setup
cd "$TEST_WORK_DIR" || exit 1
identity_home="$TEST_WORK_DIR/identity-home"
mkdir -p "$identity_home" identity/actual
ln -s "$TEST_WORK_DIR/identity/actual" "$TEST_WORK_DIR/identity/declared-link"
ln -s "$TEST_WORK_DIR/identity/actual" "$TEST_WORK_DIR/identity/other-link"
identity_declared="$TEST_WORK_DIR/identity/declared-link"
identity_borrower="$TEST_WORK_DIR/identity/other-link"
identity_shim_bin="$TEST_WORK_DIR/identity-shim-bin"
mkdir -p "$identity_shim_bin"
cat > "$identity_shim_bin/stat" <<'EOF'
#!/bin/sh
# 先擋自己：BETTER_RM_REAL_STAT 若解析回這支 shim，exec 會變成無限自我取代（單一行程
# 永遠不結束，看起來像整套測試卡住）。實測踩過一次，所以這裡失敗要大聲。
# Refuse to be our own delegate: if BETTER_RM_REAL_STAT resolves back to this
# script, the exec below replaces the process with itself forever -- one process,
# no output, the whole suite apparently hung. Measured once; fail loudly instead.
case "$BETTER_RM_REAL_STAT" in
  ''|*identity-shim-bin/stat)
    printf 'identity stat shim: BETTER_RM_REAL_STAT is missing or points at the shim: %s\n' \
        "$BETTER_RM_REAL_STAT" >&2
    exit 70
    ;;
esac
if [ "$#" -eq 3 ] && [ "$3" = "$BETTER_RM_BORROWER" ]; then
    out=$("$BETTER_RM_REAL_STAT" "$1" "$2" "$BETTER_RM_LENDER") || exit $?
    if [ "${BETTER_RM_DEV_BUMP:-1}" = 1 ]; then
        case "$out" in
          *:*) out="$(( ${out%%:*} + 1 )):${out#*:}" ;;
        esac
    fi
    printf '%s\n' "$out"
    exit 0
fi
exec "$BETTER_RM_REAL_STAT" "$@"
EOF
chmod +x "$identity_shim_bin/stat"
# 在 PATH 被改掉之前先解析出真正的 stat。放進同一個命令前綴裡會太晚：那一串賦值是左到右
# 生效的，$(command -v stat) 會在新 PATH 之下解析，於是「真 stat」指回 shim 自己。
# Resolve the real stat BEFORE the PATH prefix exists. Doing it inside the same
# assignment list is too late: those assignments take effect left to right, so
# $(command -v stat) would resolve under the shimmed PATH and name the shim.
identity_real_stat="$(command -v stat)"
identity_shimmed_says_yes() {
    # $1 = path to judge, $2 = 1 to bump the device, 0 to answer verbatim
    PATH="$identity_shim_bin:$PATH" \
    BETTER_RM_REAL_STAT="$identity_real_stat" \
    BETTER_RM_BORROWER="$identity_borrower" \
    BETTER_RM_LENDER="$identity_declared" \
    BETTER_RM_DEV_BUMP="$2" \
    HOME="$identity_home" BETTER_RM_PROTECTED_DIRS="$identity_declared" bash -c '
        eval "$(sed -n "/^PROTECTED_DIRS=(/,/^)/p;/^PROTECTED_PATTERNS=(/,/^)/p" "$1")"
        eval "$(sed -n "/^normalize_path()/,/^}/p;/^is_protected()/,/^}/p" "$1")"
        if [ "$(type -t is_protected)" != function ] ||
           [ "${#PROTECTED_DIRS[@]}" -eq 0 ]; then
            exit 99
        fi
        is_protected "$2"
    ' better-rm-is-protected "$BETTER_RM" "$1"
}
identity_dev_problem=""
# 正對照：shim 照原樣回答（不加一）時，借方與出借方同 dev 同 ino，必須被拒絕——證明
# 這條路徑真的走到身分比對，下面那個 ALLOW 才有意義。
# Positive control: answering verbatim makes the two identical, so the refusal
# proves the comparison runs at all and the ALLOW below means the device differed.
identity_shimmed_says_yes "$identity_borrower" 0 ||
    identity_dev_problem="$identity_dev_problem 對照未被拒絕(同dev同ino)"
if identity_shimmed_says_yes "$identity_borrower" 1; then
    identity_dev_problem="$identity_dev_problem 另一個device上同inode的連結被誤擋"
fi
if [ -z "$identity_dev_problem" ]; then
    test_pass "device 那一半有被比對：同 inode 但不同 device 的連結未被誤擋"
else
    test_fail "device 半邊未被比對:${identity_dev_problem}"
fi

test_item "\$HOME 被拒絕且內容完好（端到端）"
# 上一項證明清單被認定為受保護，這一項證明那個判斷真的攔在 move_to_trash 前面。
# HOME 指向 sandbox，所以就算保護整個壞掉，被搬走的也只是 sandbox。
# The previous item proves the list is recognised; this one proves that decision
# really gates move_to_trash. HOME points at a sandbox, so a broken guard moves the
# sandbox and nothing else.
setup
cd "$TEST_WORK_DIR" || exit 1
sandbox_home="$TEST_WORK_DIR/sandbox-home"
mkdir -p "$sandbox_home/keep"
printf 'KEEP\n' > "$sandbox_home/keep/marker.txt"
home_refusal=$(HOME="$sandbox_home" "$BETTER_RM" -rf "$sandbox_home" 2>&1)
if printf '%s' "$home_refusal" | grep -q "拒絕刪除受保護的目錄" &&
   [ -f "$sandbox_home/keep/marker.txt" ]; then
    test_pass "\$HOME 被拒絕且內容完好"
else
    test_fail "\$HOME 未受保護（標記存在=$([ -f "$sandbox_home/keep/marker.txt" ] && echo yes || echo no)）"
fi

test_item "\$HOME 內的一般目錄仍可刪除"
# 負對照：保護的是家目錄本身，不是家目錄底下的一切。
# Negative control: what is protected is the home directory itself, not everything
# underneath it.
if HOME="$sandbox_home" "$BETTER_RM" -rf "$sandbox_home/keep" >/dev/null 2>&1 &&
   [ ! -e "$sandbox_home/keep" ]; then
    test_pass "家目錄底下的一般目錄未被誤擋"
else
    test_fail "誤擋家目錄底下的一般目錄"
fi

test_item "readlink -f 失敗時印出的半途結果不得被採信"
# BSD 的 readlink -f 解析不到就 exit 1，但仍然把「走到一半」的結果印到 stdout。
# 實測：一條指向 /Volumes/NotMounted12345/a/b/c.txt 的斷連結（外接碟拔掉後就長這樣）
# 印出 /Volumes/NotMounted12345 並 exit 1。is_protected 只看 stdout 非空就採用，那半截
# 路徑於是撞上掛載根規則——外接碟一拔，指進去的每一條路徑都變成刪不掉的「受保護目錄」，
# 訊息還把它講成一個目錄。
# 這裡用 PATH stub 重現那個契約（印半截 + exit 1），不靠一顆真的沒掛載的磁碟：契約在
# 兩個平台上都要成立，而 GNU readlink 失敗時不印東西、本來就走得到 fallback，拿真磁碟
# 當條件只會讓這一列在 Linux 上永遠是綠的。stub 走 PATH 的手法沿用上面 symlink race
# 那一項既有的做法。探測路徑刻意用一般檔案而不是 symlink：這一列驗的是「失敗的解析
# 怎麼被消費」，不能被「symlink 依自身路徑判定」那條規則蓋過去。
# BSD readlink -f exits 1 when it cannot finish resolving, yet still prints the
# partial resolution on stdout. Measured: a link to /Volumes/NotMounted12345/a/b/c.txt
# -- what a link into an unplugged external disk looks like -- prints
# /Volumes/NotMounted12345 and exits 1. is_protected accepts any non-empty stdout, so
# that half-resolved path hits the mount-root rule and every path into the unplugged
# disk becomes an undeletable "protected directory", named as a directory at that.
# The contract (partial stdout, non-zero status) is reproduced with a PATH stub rather
# than a really unmounted disk: it has to hold on both platforms, and GNU readlink
# prints nothing on failure and already reaches the fallback, so a real disk would
# leave this row permanently green on Linux. The PATH-stub idiom is the one the
# symlink race item above already uses. The probe path is deliberately a regular file,
# not a symlink: this row is about how a FAILED resolution is consumed and must not be
# masked by the "a symlink is judged by its own path" rule.
setup
cd "$TEST_WORK_DIR" || exit 1
readlink_home="$TEST_WORK_DIR/readlink-home"
mkdir -p "$readlink_home"
printf 'PROBE\n' > "$TEST_WORK_DIR/readlink-probe.txt"
readlink_fail_bin="$TEST_WORK_DIR/readlink-fail-bin"
readlink_ok_bin="$TEST_WORK_DIR/readlink-ok-bin"
mkdir -p "$readlink_fail_bin" "$readlink_ok_bin"
cat > "$readlink_fail_bin/readlink" <<'EOF'
#!/bin/sh
# BSD 對斷連結的實測行為：印出半途結果，狀態非零。
# Measured BSD behaviour on a dangling link: partial resolution, non-zero status.
printf '%s\n' "/Volumes/NotMounted12345"
exit 1
EOF
cat > "$readlink_ok_bin/readlink" <<'EOF'
#!/bin/sh
# 同一個字串，但這次是成功的解析：必須照舊採用。
# The same string, but a successful resolution this time: it must still be used.
printf '%s\n' "/Volumes/NotMounted12345"
exit 0
EOF
chmod +x "$readlink_fail_bin/readlink" "$readlink_ok_bin/readlink"
readlink_faults=""
# 失敗的解析不得把一般檔案變成受保護目錄。
# A failed resolution must not turn an ordinary file into a protected directory.
( PATH="$readlink_fail_bin:$PATH"; is_protected_says_yes "$TEST_WORK_DIR/readlink-probe.txt" "$readlink_home" )
case $? in
    0) readlink_faults="$readlink_faults 失敗的解析仍被採信" ;;
    99) readlink_faults="$readlink_faults 探針壞掉（失敗版）" ;;
esac
# 丟掉失敗的解析不得順手拆掉清單保護：未解析的拼寫本來就該擋下 $HOME。
# Discarding a failed resolution must not dismantle the list: the unresolved
# spelling still has to refuse $HOME.
( PATH="$readlink_fail_bin:$PATH"; is_protected_says_yes "$readlink_home" "$readlink_home" )
case $? in
    0) ;;
    99) readlink_faults="$readlink_faults 探針壞掉（HOME）" ;;
    *) readlink_faults="$readlink_faults 丟掉失敗的解析後 \$HOME 不再受保護" ;;
esac
# 判準是 exit status，不是「乾脆不看 readlink」：中途元件是 symlink 時，解析出來的
# 路徑才是真的會被動到的東西，成功的解析仍然要採用。
# The criterion is the exit status, not "stop consulting readlink": when an
# intermediate component is a symlink the resolved path is what actually gets
# touched, so a successful resolution must still be honoured.
( PATH="$readlink_ok_bin:$PATH"; is_protected_says_yes "$TEST_WORK_DIR/readlink-probe.txt" "$readlink_home" )
case $? in
    0) ;;
    99) readlink_faults="$readlink_faults 探針壞掉（成功版）" ;;
    *) readlink_faults="$readlink_faults 成功的解析被忽略" ;;
esac
if [ -z "$readlink_faults" ]; then
    test_pass "失敗的 readlink -f 輸出被丟棄，成功的照舊採用，清單保護不受影響"
else
    test_fail "readlink -f 失敗輸出的處理有誤:$readlink_faults"
fi

test_item "符號連結依自身路徑判定，但會穿過去的拼寫仍依解析後的路徑判定"
# 刪除一條符號連結不會動到它指向的東西——move_exact 用的是 -h／-T，上面「連結本身進
# 垃圾桶，絕不跟隨」那一項就是在釘這件事。既然如此，拿 target 去比對保護清單就是憑
# 空造出來的誤判：受保護清單補上 macOS 那幾筆之後，~/applink -> /Applications 這種
# 再普通不過的捷徑整批變成刪不掉，-f 也蓋不過去。
# 危險的是「會穿過去的拼寫」：macOS 上 link/ 解析到的是目錄而不是連結，所以判定不能
# 一律改用未解析的路徑。實測 [ -L "link/" ]、[ -L "link/." ] 在 macOS 與 Linux 上都是
# false（結尾斜線依 POSIX 會強制解析最後一段），所以「引數自己就是一條連結」這個條件
# 剛好把兩類拼寫分在正確的兩邊；下面兩組列把這件事釘死，不是靠推論。
# Deleting a symlink cannot touch what it points at -- move_exact uses -h/-T, which
# is what the "the link itself is trashed and never followed" item above pins. So
# judging it by its target is a false positive by construction: once the macOS
# entries joined the protected list, an ordinary shortcut such as
# ~/applink -> /Applications became undeletable and -f did not override it.
# The dangerous half is the spellings that resolve THROUGH the link: on macOS
# `link/` denotes the directory, not the link, so the judgement cannot simply switch
# to the unresolved path for everything. Measured on both platforms:
# [ -L "link/" ] and [ -L "link/." ] are false, because a trailing slash forces
# resolution of the final component -- so "the argument is itself a symlink" splits
# the two classes exactly right. The two row groups below pin that rather than
# reasoning about it.
setup
cd "$TEST_WORK_DIR" || exit 1
# 沙箱 $HOME 必須用實體路徑（pwd -P）：macOS 的 /tmp 本身就是 /private/tmp 的連結，
# 拿 /tmp/… 那個寫法當 $HOME 的話，解析後的路徑永遠對不上清單裡的 $HOME，於是「穿過
# 連結」那幾列在 macOS 上恆綠、在 Linux 上才紅——正好是最會漏掉的那種平台差異。
# The sandbox $HOME has to be the physical path (pwd -P): on macOS /tmp is itself a
# link to /private/tmp, so a $HOME spelled /tmp/… never matches the resolved path and
# the resolve-through rows would be permanently green on macOS and red only on Linux
# -- exactly the platform difference that is easiest to ship by accident.
symlink_work=$(pwd -P)
symlink_home="$symlink_work/symlink-home"
mkdir -p "$symlink_home/keep" "$symlink_work/plain-dir"
ln -s "$symlink_home" "$symlink_work/link-to-home"
ln -s "$symlink_home/keep" "$symlink_work/link-to-keep"
ln -s /usr "$symlink_work/link-to-usr"
ln -s / "$symlink_work/link-to-root"
ln -s "$symlink_work/plain-dir" "$symlink_work/.git"
symlink_false_positive=""
symlink_probe_broken=""
# 引數自己就是一條連結：刪掉它動不到 target，一律依自身路徑判定。
# The argument is itself a link: deleting it cannot reach the target, so it is
# judged by its own path.
for symlink_allowed_path in "$symlink_work/link-to-home" "$symlink_work/link-to-usr" \
                            "$symlink_work/link-to-root" "$symlink_work/link-to-keep"; do
    is_protected_says_yes "$symlink_allowed_path" "$symlink_home"
    case $? in
        0) symlink_false_positive="$symlink_false_positive $symlink_allowed_path" ;;
        99) symlink_probe_broken="$symlink_probe_broken $symlink_allowed_path" ;;
    esac
done
symlink_unguarded=""
# 真目錄本身的每一種拼寫、會穿過連結的每一種拼寫，以及「自己就是連結但名字本身受保護」
# 的清單項與模式項（Linux 的 /bin、macOS 的 /etc、名為 .git 的連結）都必須照舊拒絕。
# Every spelling of the real directories, every spelling that resolves through a
# link, and the list/pattern entries that are themselves symlinks (/bin on Linux,
# /etc on macOS, a link named .git) all have to stay refused.
for symlink_protected_path in "$symlink_home" "$symlink_home/" \
                              /usr /usr/ //usr /usr/. / \
                              /bin /etc /var \
                              "$symlink_work/link-to-home/" \
                              "$symlink_work/link-to-home/." \
                              "$symlink_work/link-to-usr/" \
                              "$symlink_work/link-to-keep/.." \
                              "$symlink_work/.git"; do
    is_protected_says_yes "$symlink_protected_path" "$symlink_home"
    case $? in
        0) ;;
        99) symlink_probe_broken="$symlink_probe_broken $symlink_protected_path" ;;
        *) symlink_unguarded="$symlink_unguarded $symlink_protected_path" ;;
    esac
done
if [ -z "$symlink_false_positive" ] && [ -z "$symlink_unguarded" ] &&
   [ -z "$symlink_probe_broken" ]; then
    test_pass "連結依自身路徑判定，穿過連結的拼寫與清單／模式項照舊受保護"
else
    test_fail "連結誤擋:${symlink_false_positive:- 無}；穿過去或清單項未受保護:${symlink_unguarded:- 無}；抽取失敗:${symlink_probe_broken:- 無}"
fi

test_item "指向 \$HOME 的連結可以刪除，且進垃圾桶的是連結本身（端到端）"
# 上一項證明判斷改了，這一項證明改的是真的會發生的事，而且刪掉的確實是連結：垃圾桶裡
# 那一筆必須是 symlink 而且還指著原來的地方，$HOME 底下的內容一個字都不能少。
# HOME 指向 sandbox，所以就算跟隨了連結，被搬走的也只是 sandbox。
# The previous item proves the judgement changed; this one proves the change reaches
# real behaviour and that what was removed is the link: the trash entry has to be a
# symlink still pointing where it did, and nothing under $HOME may move.
# HOME points at a sandbox, so even a followed link would only move the sandbox.
setup
cd "$TEST_WORK_DIR" || exit 1
# 沙箱 $HOME 用實體路徑，理由同上一項。
# The sandbox $HOME is the physical path, for the reason given in the previous item.
linkhome_home="$(pwd -P)/linkhome-home"
mkdir -p "$linkhome_home/keep"
printf 'KEEP\n' > "$linkhome_home/keep/marker.txt"
ln -s "$linkhome_home" homelink
linkhome_status=0
linkhome_output=$(HOME="$linkhome_home" "$BETTER_RM" homelink 2>&1) || linkhome_status=$?
linkhome_trashed=$(find "$TEST_TRASH_DIR" -maxdepth 12 -type l -name 'homelink__*' 2>/dev/null |
    head -n 1)
if [ "$linkhome_status" -eq 0 ] && [ ! -L homelink ] &&
   [ -n "$linkhome_trashed" ] &&
   [ "$(readlink "$linkhome_trashed")" = "$linkhome_home" ] &&
   [ "$(cat "$linkhome_home/keep/marker.txt" 2>/dev/null)" = "KEEP" ]; then
    test_pass "連結本身進了垃圾桶，\$HOME 的內容原封不動"
else
    test_fail "指向 \$HOME 的連結未被正確刪除（exit=${linkhome_status}；垃圾桶連結=${linkhome_trashed:-無}；訊息=${linkhome_output}）"
fi

test_item "結尾斜線的連結拼寫仍被當成它指到的目錄而拒絕（端到端）"
# 這是上一項的安全網：macOS 的 `rm -rf ~/applink/` 動的是 target 的內容，所以這個拼寫
# 一旦被放行，放行的就是刪除 $HOME 本身。連結與 marker 都必須原封不動。
# 把上面的判斷條件改成先剝掉結尾斜線（例如 [ -L "${path%/}" ]），這一列就會轉紅。
# The safety net for the previous item: on macOS `rm -rf ~/applink/` operates on the
# target's contents, so allowing this spelling would allow deleting $HOME itself.
# Both the link and the marker have to survive untouched. Rewriting the condition to
# strip the trailing slash first (say [ -L "${path%/}" ]) turns this row red.
setup
cd "$TEST_WORK_DIR" || exit 1
slashlink_home="$(pwd -P)/slashlink-home"
mkdir -p "$slashlink_home/keep"
printf 'KEEP\n' > "$slashlink_home/keep/marker.txt"
ln -s "$slashlink_home" homelink
slashlink_output=$(HOME="$slashlink_home" "$BETTER_RM" -rf homelink/ 2>&1)
if printf '%s' "$slashlink_output" | grep -q "拒絕刪除受保護的目錄" &&
   [ -L homelink ] &&
   [ "$(cat "$slashlink_home/keep/marker.txt" 2>/dev/null)" = "KEEP" ]; then
    test_pass "結尾斜線的拼寫照舊被拒絕，連結與 \$HOME 內容都在"
else
    test_fail "結尾斜線的拼寫未被拒絕（連結存在=$([ -L homelink ] && echo yes || echo no)；marker=$(cat "$slashlink_home/keep/marker.txt" 2>/dev/null)；訊息=${slashlink_output}）"
fi

test_item "還原：目的地被指向 \$HOME 的連結佔著時，讓位仍走垃圾桶而不是整個中止"
# is_protected 說「受保護」時 --restore 不讓位也不覆蓋，直接中止；於是目的地只要被一條
# 指向受保護目錄的連結佔著，那筆還原就永遠做不成，即使那條連結刪掉完全無害。
# 這一列驗的是還原真的完成、而且佔位的連結是「移入垃圾桶」而不是被銷毀。
# --restore neither displaces nor overwrites a destination is_protected calls
# protected: it aborts. So a destination occupied by a link to a protected directory
# made the restore permanently impossible, even though removing that link is
# harmless. This row checks the restore actually completes and that the occupying
# link went INTO the trash rather than being destroyed.
setup
cd "$TEST_WORK_DIR" || exit 1
restorelink_home="$(pwd -P)/restorelink-home"
mkdir -p "$restorelink_home/keep"
printf 'KEEP\n' > "$restorelink_home/keep/marker.txt"
printf '%s\n' "RESTORED CONTENT" > occupant.txt
HOME="$restorelink_home" "$BETTER_RM" occupant.txt >/dev/null 2>&1
ln -s "$restorelink_home" occupant.txt
restorelink_status=0
restorelink_output=$(HOME="$restorelink_home" "$BETTER_RM" -f --restore -- occupant.txt 2>&1) ||
    restorelink_status=$?
restorelink_trashed=$(find "$TEST_TRASH_DIR" -maxdepth 12 -type l -name 'occupant.txt__*' 2>/dev/null |
    wc -l | tr -d ' ')
if [ "$restorelink_status" -eq 0 ] &&
   [ -f occupant.txt ] && [ ! -L occupant.txt ] &&
   [ "$(cat occupant.txt 2>/dev/null)" = "RESTORED CONTENT" ] &&
   [ "$restorelink_trashed" -eq 1 ] &&
   [ "$(cat "$restorelink_home/keep/marker.txt" 2>/dev/null)" = "KEEP" ]; then
    test_pass "佔位的連結移入垃圾桶讓位，還原完成且 \$HOME 內容原封不動"
else
    test_fail "還原未完成或佔位連結未進垃圾桶（exit=${restorelink_status}；垃圾桶連結=${restorelink_trashed}；訊息=${restorelink_output}）"
fi

# ============================================================================
# 測試結果統計 (Test Results Summary)
# ============================================================================
cleanup

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}測試結果統計 (Test Results Summary)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "總測試數 (Total Tests): ${BLUE}$TOTAL_TESTS${NC}"
echo -e "通過測試 (Passed): ${GREEN}$PASSED_TESTS${NC}"
echo -e "失敗測試 (Failed): ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ 所有測試通過！(All tests passed!)${NC}"
    exit 0
else
    echo -e "${RED}✗ 有 $FAILED_TESTS 個測試失敗 ($FAILED_TESTS tests failed)${NC}"
    exit 1
fi
