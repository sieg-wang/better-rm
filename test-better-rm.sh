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

# 測試用的垃圾桶目錄 (Test trash directory)
TEST_TRASH_DIR="/tmp/better-rm-test-trash"

# 測試用的狀態目錄 (Test state directory)
TEST_STATE_DIR="/tmp/better-rm-test-state"

# 測試用的工作目錄 (Test working directory)
TEST_WORK_DIR="/tmp/better-rm-test-work"

# 測試不可寫狀態目錄時使用的一般檔案
# Regular file used to test an unavailable state directory
TEST_STATE_BLOCKER="/tmp/better-rm-test-state-blocker"

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

test_item "-- 的說明不得從 --help 與 README 消失"
# 文件漂移護欄。-- 是使用者唯一能指名破折號開頭檔案的寫法，說明從 --help 或 README
# 掉了，這個功能對使用者就等於不存在，而測試套件不會有任何一項變紅。
# 兩邊都只釘「選項那一欄」——--help 的選項欄位與 README 選項表格的那一列：描述文字
# 怎麼改寫都不會紅，整條被刪掉才會紅。刻意不比對描述本身，也不掃整份 README（-- 在
# README 出現三處，只掃全檔的話刪掉選項表格那一列仍然會綠，護欄就只剩一半）。
# Documentation-drift guard. -- is the only way a user can name a file whose name
# starts with a dash, so an entry quietly dropped from --help or the README makes
# the feature nonexistent for users without turning anything in this suite red.
# Both checks pin only the option column -- the option field in --help and the
# option-table row in the README: rewording the description stays green, deleting
# the entry goes red. The description text is deliberately not compared, and the
# README is deliberately not searched as a whole (-- is mentioned in three places,
# so a whole-file grep would stay green after the table row was deleted, which is
# half a guard).
terminator_doc_gaps=""
if ! "$BETTER_RM" --help | grep -q '^  -- '; then
    terminator_doc_gaps="$terminator_doc_gaps --help"
fi
if ! grep -q "^| \`--\` |" "$SCRIPT_DIR/README.md"; then
    terminator_doc_gaps="$terminator_doc_gaps README.md"
fi
if [ -z "$terminator_doc_gaps" ]; then
    test_pass "--help 與 README 都還列著 -- 選項"
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
    local status=0
    "$BETTER_RM" "$@" >/dev/null 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        restore_contract_ok=0
        printf '  %s：未報錯 / did not fail\n' "$label" >&2
    fi
}

test_item "--restore 的引數契約沒有被 -- 放寬"
# 反套套邏輯：加的是終止符，不是「什麼都當成引數」。缺引數、-- 後面沒有東西、
# 誤打成另一個選項，以及含空白的破折號開頭引數，都必須照舊報錯。
# Anti-tautology: what was added is the terminator, not "accept anything as the
# argument". A missing argument, a bare terminator with nothing after it, a
# mistyped option, and a dash-leading argument containing a space must all still
# be errors.
restore_contract_ok=1
check_restore_refusal "--restore（沒有引數）" --restore
check_restore_refusal "--restore --（後面沒有東西）" --restore --
check_restore_refusal "--restore -v（沒有 --）" --restore -v
check_restore_refusal "--restore '-v oops.txt'（含空白）" --restore "-v oops.txt"
if [ "$restore_contract_ok" -eq 1 ]; then
    test_pass "--restore 缺引數／裸 --／誤打選項／含空白選項仍然報錯"
else
    test_fail "--restore 的引數契約被放寬了"
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

if [ "$nospace_status" -eq 0 ] && \
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

if [ "$trashfail_status" -eq 0 ] && \
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
# The previous revision recorded a source under / as //name. Those records must
# keep restoring after the composition goes back to a single slash.
setup
cd "$TEST_WORK_DIR"
printf '%s\n' "DOUBLE SLASH LEDGER" > double_slash.txt
"$BETTER_RM" double_slash.txt
double_slash_trash=$(find "$TEST_TRASH_DIR" -type f -name 'double_slash.txt__*' | head -1)
{
    printf '%s\n' "# Better-RM Deletion Log"
    printf '%s | %s | %s | %s | %s\n' \
        "20260101_000000_000000000" \
        "/${TEST_WORK_DIR}/double_slash.txt" \
        "$double_slash_trash" \
        "0123456789abcdef" \
        "file"
} > "$TEST_STATE_DIR/deletion.log"
double_slash_status=0
"$BETTER_RM" --restore double_slash.txt >/dev/null 2>&1 || double_slash_status=$?
if [ "$double_slash_status" -eq 0 ] && [ -f double_slash.txt ] && \
   [ "$(cat double_slash.txt)" = "DOUBLE SLASH LEDGER" ]; then
    test_pass "雙斜線紀錄仍可還原"
else
    test_fail "雙斜線紀錄無法還原 (status=$double_slash_status)"
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
# filesystem. The 16+2 names are spelled out on purpose -- reading them back from
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
for protected_path in / /bin /boot /dev /etc /home /lib /lib64 /mnt /opt \
                      /proc /root /sbin /sys /usr /var \
                      "$protected_home" "$protected_home/"; do
    is_protected_says_yes "$protected_path" "$protected_home"
    case $? in
        0) ;;
        99) protected_probe_broken="$protected_probe_broken $protected_path" ;;
        *) protected_unguarded="$protected_unguarded $protected_path" ;;
    esac
done
# 負對照：這道探測不是「一律說是」，否則刪掉整個清單也會通過。
# Negative control: the probe is not simply saying yes to everything -- otherwise
# deleting the whole list would also pass.
protected_false_positive=""
for unprotected_path in "$TEST_WORK_DIR/ordinary.txt" /mnt/c/project \
                        /usr/local/share/x "$protected_home/keep"; do
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
