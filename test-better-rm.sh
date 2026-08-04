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
