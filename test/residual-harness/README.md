# residual-harness — 重跑 KNOWN-RESIDUALS.md 的每一條，而不是重新推導一次

這個目錄是 `KNOWN-RESIDUALS.md` 的**可執行版本**。那份文件記了三個實測、刻意不修的
殘留（R1/R2/R3），以及釘住它們的那個測試自己的四個已知極限。每一條的數字都是量出來
的，量它們的腳本原本只活在一個七天內會被清掉的 session scratchpad 裡。這裡是它們的
永久版本。

**用途只有一個：下一個審查者想質疑其中任何一條時，可以直接跑，而不是花半天重新推導
出同一個結論。**（前四輪 review 每一輪都重推過一次 R1–R3，這個目錄就是為了讓第五輪
不要再來一次。）

This directory is the executable form of `KNOWN-RESIDUALS.md`. Every figure in that
document was measured; the scripts that measured it used to live only in a session
scratchpad that this machine wipes within 7 days. A reviewer who wants to challenge
any claim there should re-run it here rather than re-derive it from scratch.

> **這些腳本不是測試套件的一部分，也不該是。** 它們慢（多數要跑好幾次完整的
> `test-better-rm.sh`）而且部分對負載敏感。`run-test-suites.sh`、CI workflow 都是
> 逐一列名的，不吃萬用字元，所以不會意外把這裡掃進去——請維持這個性質。
>
> These are NOT part of the test suite and must not become part of it: they are slow
> and some are load-sensitive. `run-test-suites.sh` and the CI workflow both name
> every suite explicitly and use no globs, so nothing here runs by accident.

---

## 安全性：每一支都必須成立的三條

這些腳本會**驅動一支刪除工具**，而且會對整個 repo 做可寫的副本並在上面做突變。所以
底座（`lib/harness.sh`）強制三件事，每一支都套用同一個模式：

1. **repo 從腳本自己的位置推導**，不寫死任何絕對路徑：
   `HS_REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"`，
   而且會驗那裡真的長得像 better-rm（缺任何一個必要檔就整支拒跑）。
2. **工作區一律 `mktemp -d` 在 `${TMPDIR:-/tmp}` 底下，EXIT/INT/TERM 都清掉**，
   而且只清名字帶得出 harness 前綴的目錄。
3. **只要工作路徑解析後落在 repo 裡面就整支拒跑並說明原因**（`hs_refuse_inside_repo`）。
   這條不是潔癖：2026-08-18 有一支 repo 工具的輸出路徑是從**腳本自己的位置**推導的，
   被拿去對活的工作樹跑，毀掉了真實使用者資料。這裡在 `mktemp` **之後**再驗一次，
   因為 `TMPDIR` 有可能是指進 repo 的 symlink。

另外，`better-rm` 會讀**五個**環境變數：`HOME` / `TRASH_DIR` / `BETTER_RM_STATE_DIR` /
`XDG_STATE_HOME` / `BETTER_RM_PROTECTED_DIRS`（`TRASH_DIR` 預設 `$HOME/.Trash`，state
dir 沒設就走 `XDG_STATE_HOME`）。`hs_isolated` 把**前四個**指進工作區，再加上 `TMPDIR`
與一個工作區內的 cwd。真實使用者檔案在任何一支腳本裡都碰不到。

第五個**刻意不動**：`BETTER_RM_PROTECTED_DIRS` 是使用者「新增保護」的唯一介面，只會
多擋、不會少擋（`better-rm:523-560`），所以繼承它不可能讓真實檔案被碰到。把它清空
反而是在一支「會刪東西的腳本」裡靜默拿掉一道保護。代價是它**會改變探針的輸出**——
例如指到 `$TMPDIR` 底下就會讓工作區裡的 victim 被拒絕刪除。所以選擇是：繼承，但在
workspace 建立時把值印出來，讓奇怪的結果解釋得掉。看到那段 NOTE 又想比對乾淨結果，
就 `env -u BETTER_RM_PROTECTED_DIRS` 再跑一次。

第三件事跟 `rm` 本身有關：底座呼叫的是**真正的 rm 執行檔**（`/bin/rm`），不是讓 shell
去解析那個字。`better-rm` 目前是以 shell alias 安裝的，而非互動 shell 不展開 alias，
所以裸的 `rm` 本來就會打到 `/bin/rm`——但那是「安裝方式」的性質，不是這份 harness 的
性質。哪天改成 PATH shim，TOCTOU racer 那個熱迴圈一秒就會往使用者**真正的**垃圾桶與
刪除日誌灌幾百筆。不靠那個巧合。

自己驗這兩道閘：

```bash
# 1) 工作區落在 repo 裡 -> 必須以 rc=90 拒跑
#    residual-harness: FATAL: REFUSING TO RUN: work path '…' resolves to '…',
#    which is inside the repo (…)
TMPDIR="$PWD" ./test/residual-harness/probe-run-bounded.sh

# 2) 腳本被搬走、../.. 不再是 repo -> 必須以 rc=90 拒跑
#    residual-harness: FATAL: '…' does not look like the better-rm repo (missing better-rm)
D=$(mktemp -d); mkdir -p "$D/a/b/lib"
cp test/residual-harness/probe-run-bounded.sh "$D/a/b/"
cp test/residual-harness/lib/harness.sh       "$D/a/b/lib/"
"$D/a/b/probe-run-bounded.sh"; /bin/rm -rf "$D"
```

Safety contract, per script: the repo is located from the script's own position and
validated; the workspace is always `mktemp -d` under `${TMPDIR:-/tmp}` and is removed
on exit; and the script refuses to run at all if any work path resolves inside the
repo. Every variable better-rm reads is pointed into that workspace.

---

## 相容性

必須在 stock `/bin/bash` 3.2.57 上跑得動（本機是 macOS，這個 repo 的 CI 是 ubuntu-only，
但工具本身兩邊都要能用）。因此：

- 不用 `{fd}>>`（bash 3.2 沒有）。
- 不用 GNU-only 的 `stat` 旗標。**特別注意 `stat -f … || stat -c …` 這個 fallback
  慣用法是壞的**：GNU 的 `stat -f` 印的是「檔案系統狀態」、吐一大串到 stdout 才以 1
  結束，反過來寫會把那堆字讀成答案。底座乾脆完全不用 `stat`。
- 不用 BSD-only 的 `sed -i ''`；所有文字突變走 `perl -i`，兩個平台行為相同。
- 高解析度時間用 perl 的 `Time::HiRes`（core module，兩邊都在），不用 `date +%N`
  （BSD date 沒有），也不假設有 python3。
- `timeout` 不是 macOS 內建。需要它的兩支腳本會先偵測 `timeout` / `gtimeout`，
  兩個都沒有就直說並退出——**不會假裝量到了**。

---

## 一覽

耗時幾乎全部由「跑了幾次完整的 `test-better-rm.sh`」決定。2026-08-20 在閒置的 M 系列
mac 上實測：**一次約 24–27 秒**（`mutants-log-binding.sh` 7 次 189 秒、`repeat-core.sh`
5 次 119 秒、`vacuity-log-path-tests.sh` 2 次 49 秒，都是量到的）。其餘用 `N × 27s` 推。

| 腳本 | 對應 | 跑幾次完整 suite | 耗時 |
|---|---|---|---|
| `pin-redproof.sh` | 釘子本身（R1/R2/R3 雙向） | 9 | ≈ 4 分 |
| `pin-anchor-uniqueness.sh` | 已知極限 2 | 13 ＋ 1 次 stock bash | ≈ 6.5 分 |
| `pin-comment-forms.sh` | 已知極限 3 | 15 | ≈ 7 分 |
| `pin-nul-evasion.sh` | 已知極限 4 | 5 | ≈ 2.5 分 |
| `mutants-log-binding.sh` | **R2** | 7 | **189 秒（實測）** |
| `probe-toctou-rate.sh` | **R1** | 0 | ≈ 1 分（150 次刪除） |
| `probe-log-path-variants.sh` | R2 的 hardlink 那一列 ＋ 修復回歸 | 0 | ≈ 10 秒 |
| `probe-fifo-margin.sh` | R3 的同族風險（牆鐘斷言） | 0 | ≈ 5 秒 |
| `probe-run-bounded.sh` | ca02eca 的可攜性 | 0 | ≈ 7 秒 |
| `vacuity-log-path-tests.sh` | ca02eca 兩個新測試的非空洞性 | 2 | **49 秒（實測）** |
| `repeat-core.sh` | R3 的方法學 | N（預設 5） | **119 秒（實測，N=5）** |

全部跑完約 25 分鐘。**一次跑一支**：好幾支同時跑會互相加負載，而牆鐘相關的量測
（`probe-fifo-margin.sh`、`repeat-core.sh`）在那種條件下沒有意義。

「已知極限 1」（在文件裡插一句「以上作廢」原地否定，測試照樣綠）**沒有腳本，也不會有**：
grep 型釘子在定義上抓不到原地否定，寫一支只印「GREEN」的腳本沒有資訊量。

跑之前先確認 repo 是乾淨的（`git status --porcelain` 空的）。這些腳本都在副本上工作、
不會動到工作樹，但它們**讀的是工作樹的現況**，所以未提交的改動會進到量測裡。

---

## 一支一支

### `pin-redproof.sh` — 那個雙向釘真的紅得起來嗎

**驗什麼**：`test-better-rm.sh` 裡釘住 R1/R2/R3 的那條測試，兩個方向都會紅。三個文字
anchor 各自被改寫、整份文件被刪掉、以及三個程式碼事實各自被改掉（`[ -O ]` clause 拿掉、
`budgetMs` 改成不看牆鐘、`log_file_is_bound` 改名成 fd 版）。

**怎麼跑**：`./test/residual-harness/pin-redproof.sh`

**今天應該印什麼**（2026-08-20 實測，`edd22fd`）：baseline 與 final GREEN，中間七個
全部 RED，每個 RED 後面接的診斷訊息要指向**它自己那一個**改動；最後三個檔案 byte-identity
全 OK，結尾 `RESULT: every case matched its documented expectation.`

```
baseline (unmutated)                          GREEN [want GREEN OK   ] total=136 failed=0
M1 doc: R1 fix-direction token mangled        RED   [...] :: anchor[O_NOFOLLOW]在文件裡出現0次(必須恰好1次); R1的修法方向(O_NOFOLLOW)從文件消失;
M2 doc: R2 untestability reason reworded      RED   [...] :: anchor[無法在無 root 的情況下測試]在文件裡出現0次(必須恰好1次); R2的不可測理由從文件消失;
M3 doc: R3 symmetry conclusion reworded       RED   [...] :: anchor[兩邊都紅]在文件裡出現0次(必須恰好1次); R3的對稱性結論從文件消失;
M4 doc: KNOWN-RESIDUALS.md deleted entirely   RED   [...] :: KNOWN-RESIDUALS.md 不存在
M5 code: the [-O] ownership clause removed    RED   [...] :: R2所指的[-O]clause已不在better-rm的活碼裡;
M6 code: budgetMs made load-insensitive       RED   [...] :: R3所指的1000ms牆鐘預算已不在test-hooks.js的活碼裡;
M7 code: log_file_is_bound renamed            RED   [...] :: R1所描述的log_file_is_bound已不存在;
final (restored — must be GREEN again)        GREEN [want GREEN OK   ] total=136 failed=0
```

**已知假陽性**：對 `[ -O ]` 做語意不變的改寫會讓釘子紅，而診斷會說「已不在活碼裡」——
方向是安全的（寧可誤報），但那句話當下是錯的。看到它請直接看程式碼，別信訊息字面。

---

### `pin-anchor-uniqueness.sh` — 「每個 anchor 恰好一次」是不是真的紅得起來

**驗什麼**：已知極限 2。釘子看得到字串、看不到位置，所以文件裡多出第二份 anchor 字面
拷貝時，整個 R 段落被刪掉照樣綠（2026-08-19 的揭露段落自己犯過這個錯，`a37d49b` 修的
就是它）。這支腳本兩邊都量：`DUP-*` 種入第二份拷貝（自成一行／程式碼圍籬內／同一行／
接在既有句尾／同一行三份），`DEL-*` 刪掉整個 R1/R2/R3 段落或只刪 R1 的修法段落。

它同時示範**計數陷阱本身**：`grep -c` 數的是「有命中的**行**數」，同一行放兩次照樣回 1
（`8ca60c5` 修的就是這個），所以釘子改用 `grep -o | wc -l | tr -d`。`tr -d` 也是必要的，
BSD `wc -l` 會補前導空白。

**怎麼跑**：`./test/residual-harness/pin-anchor-uniqueness.sh`

**今天應該印什麼**（2026-08-20 實測）：HEAD 的三個 anchor 都是 `-c=1 / -o|wc -l=1`；
計數陷阱示範那一段（在檔尾多種一行含兩份拷貝）會印出 **`-c=2` 但 `-o|wc -l=3`**——
兩個數字不一致就是陷阱本身，`grep -c` 少算了同一行上的第二份；baseline 與 final GREEN；
中間 **11 列**全部 RED（9 種突變，其中 `DUP-3` 對三個 anchor 各跑一次），而且每個診斷會
直接報出實際出現次數（2/3/4/0）；三個 locale 的計數都是 1；stock `/bin/bash` 跑核心
suite rc=0、136/136。

---

### `pin-comment-forms.sh` — 程式碼那半邊擋得住哪些改法、擋不住哪些

**驗什麼**：已知極限 3。釘子的程式碼半邊會先濾掉**行首**註解（`#` / `//`）再比對，
所以「把整行註解掉」那一種會紅（`CLOSED-*`，`5e295ef` 補的）。**其餘全都還是綠的**
（`OPEN-*`）。

> ⚠️ **`OPEN-*` 印出 GREEN 是正確結果**，代表那個洞還開著。哪天有人把它補起來，這裡
> 就會印出 `MISS`——那正是要知道的事，不是這支腳本壞了。

最危險的是行尾註解那種，因為它同時是「看起來已修好」的形狀：`node --check` 過、釘子
維持綠，**而預算已經被調大了**——正是 R3 明文說不要做的那個修法。

**怎麼跑**：`./test/residual-harness/pin-comment-forms.sh`

**今天應該印什麼**（2026-08-20 實測）：baseline / final GREEN；`CLOSED-1`、`CLOSED-2`、
`CTRL-1`、`CTRL-2` 四列 RED；`OPEN-1` 到 `OPEN-9` 九列全部 GREEN、`total=136 failed=0`。

九種仍然通得過的形狀（實測，非推測）：bash 的行尾註解、bash 的 `:` no-op 前綴、
字串字面、`if false; then … fi`、`: <<'EOF'` 區塊、搬進沒人呼叫的函式；JS 的
`/* … */`、行尾註解、`if (false) { … }`。

---

### `pin-nul-evasion.sh` — 精確計數的 BSD-only 繞法

**驗什麼**：已知極限 4。BSD `grep -o` 碰到含 NUL 的檔案會印一行 `Binary file … matches`，
於是 `wc -l` 永遠讀成 1，不論實際有幾份拷貝。完整攻擊 = 刪掉整個 R1 段落 ＋ 留兩個孤立
token ＋ 種一個 NUL，在 `LC_ALL=C` 下**整套 suite 全綠**。

> ⚠️ `ATTACK` 那一列印出 GREEN 是正確結果，代表繞法仍然成立。

**怎麼跑**：`./test/residual-harness/pin-nul-evasion.sh`

**今天應該印什麼**（2026-08-20 實測）：

```
baseline, LC_ALL=C                            GREEN  total=136 failed=0
CTRL-1 attack WITHOUT a NUL, LC_ALL=C         RED    :: anchor[O_NOFOLLOW]在文件裡出現2次(必須恰好1次);
CTRL-2 attack WITH a NUL, LC_ALL=en_US.UTF-8  RED    :: anchor[無法在無 root…]出現0次; anchor[兩邊都紅]出現0次; …
ATTACK  attack WITH a NUL, LC_ALL=C           GREEN  total=136 failed=0     <- 繞法成立
```

**兩個要注意的細節，都是這次移植量出來的**：

1. `CTRL-2`（有 NUL、UTF-8 locale）確實是紅的，但**機制跟預期不同**：ASCII 的
   `O_NOFOLLOW` 仍然被算成 1（`Binary file … matches`），紅是因為**兩個中文 anchor 讀成
   0 次**。也就是 UTF-8 locale 下 NUL 讓多位元組 anchor 完全比不到，而不是「計數變正確」。
2. **`KNOWN-RESIDUALS.md` 說的「git 會把該檔顯示成 binary，review 時很難不注意」
   在 NUL 種在檔尾時不成立。** git 只看**前 8000 bytes**，而這份文件是 10,318 bytes，
   所以 NUL 附在檔尾時 `git diff --numstat` 印的是一般的 `4  24`（純文字 diff），
   NUL 種在開頭才印 `-  -`（binary）。腳本現在兩種位置都量給你看。
   **這削弱了極限 4 唯一的實務緩解措施**，但這份 README 不動 `KNOWN-RESIDUALS.md`——
   要不要改那份文件是使用者的決定。

CI 是 ubuntu（GNU grep），**那一側目前仍是推論不是實測**。這支腳本在 Linux 上跑出什麼，
就是那一側的第一手資料。

---

### `mutants-log-binding.sh` — R2 的正本

**驗什麼**：把日誌綁定的每一個 clause 各做一個突變，跑整套核心 suite，看它會不會紅。
判定分三種，因為「被抓到」有兩種很不一樣的意思：

- `CAUGHT` —— 有**行為測試**紅了，真的有守衛。
- `PIN-ONLY` —— 只有 `KNOWN-RESIDUALS.md` 那個雙向釘紅了，**行為覆蓋率是零**，
  被抓到的只是「文件與程式碼不同步」。
- `NOT-CAUGHT` —— 整套全綠，完全沒有覆蓋。

| mutant | 改動 | 今天的判定（2026-08-20 實測） |
|---|---|---|
| `symlink` | 刪掉 `[ -L ]` | `CAUGHT`（symlink 日誌測試） |
| `regular` | 刪掉 `[ -f ]` | `CAUGHT`（FIFO 測試逾時） |
| `nlink` | link 數判斷改成 `true` | `CAUGHT`（hard link 測試） |
| `occupancy` | 佔用判斷少掉 `[ -L ]` | `CAUGHT`（斷掉 symlink 測試） |
| `owner` | 刪掉 `[ -O ]` | **`PIN-ONLY` ＝ R2** |
| `trimmed` | `[ -f ]` 改成只擋 FIFO | **`NOT-CAUGHT`（新發現，見下）** |

**怎麼跑**：`./test/residual-harness/mutants-log-binding.sh`（或只跑一個：`… owner`）

#### ⚠️ `owner` ＝ `PIN-ONLY` 是正確結果，而且就是 R2 的全部內容

`[ -O ]` **沒有任何行為測試**，而且在無 root 的情況下補不出來。root 擁有的檔案本身
**做得出來**（`ln /etc/hosts <0700 state dir>/deletion.log` 回 0，早先說「寫不出來」
是錯的），但 hardlink 必然 `nlink >= 2`，會被 link 數那一條擋下——所以刪掉 `[ -O ]`
之後，同一個 fixture 的輸出逐字相同，觀察不到差別。
**不要為了讓覆蓋率好看去硬寫一個測不到真實條件的測試**，那種測試唯一的效果是讓
下一個人以為這裡有防護。

> **這裡有一句 `KNOWN-RESIDUALS.md` 已經不再逐字成立的話。** R2 寫的是「把它刪掉，
> 整套 `test-better-rm.sh` 照樣全綠」。在 `edd22fd` 上**不是全綠**：`5e295ef` 之後那個
> 雙向釘會 grep better-rm 活碼裡的 `[ -O ]` 那一行，所以刪掉它會讓釘子紅。
> **R2 的實質完全沒變**（行為覆蓋率仍然是零），變的只是「全綠」這個措辭。
> 這份 README 不會去改 `KNOWN-RESIDUALS.md`——要不要改那句話是使用者的決定。

#### ⚠️ `trimmed` ＝ `NOT-CAUGHT` 是這次移植量出來的新發現

把「必須是一般檔」放寬成「只擋 FIFO」（`[ -f "$path" ] || return 1` →
`[ ! -p "$path" ] || return 1`），**整套 136 個測試沒有一個會紅**。可觀察的差別只有
一個：**socket 日誌會被靜默接受**，不再出現拒絕訊息。直接看：

```bash
# 造一個 trimmed build，然後只探 socket 那一種
./test/residual-harness/probe-log-path-variants.sh --brm <trimmed-build> socket
#   refusal warning shown: no
#   VERDICT: DEFECT - NO REFUSAL (the planted shape was accepted as a log)
```

換句話說：FIFO 那個測試釘住的是「**不會卡住**」，**不是**「必須是一般檔」。這是一個
既有的覆蓋缺口，這次只做記錄，沒有補測試（那會動到 `test-better-rm.sh`）。

---

### `probe-toctou-rate.sh` — R1 的正本

**驗什麼**：`log_file_is_bound()` 驗的是**路徑**，通過之後 `log_deletion` 才用同一個
路徑 append，中間有窗口。腳本開一個同 UID 的 racer 不停把日誌路徑在「正常檔」與
「指向 target 的 symlink」之間翻面，然後跑 N 次刪除，數有幾次 append 跟著連結走過去。

**怎麼跑**：`./test/residual-harness/probe-toctou-rate.sh [次數]`（預設 150）

> ### ⚠️ 這支腳本印出來的比率**不是**這個洞的難度
>
> **命中率隨 harness 的積極程度大幅變動，這是 TOCTOU 的正常現象。** 對**同一份程式碼**，
> 獨立 harness 量到過：**3.3% / 7.3% / 8.0% / 28.7%(43/150) / 50.7%(76/150) /
> 72.0% / 96.7%**。任何單一數字都只描述那一次的 harness 與那一刻的機器負載。
> **別把哪一個當成上限，也別當成下限。** 要判斷風險請看前提條件（state dir 是 0700、
> 使用者自有，攻擊者要先有同 UID 的執行能力），不是看比率。
>
> **連同一支 harness 在同一台機器上都不穩**：這支腳本 2026-08-20 連跑三次 150，
> 拿到 **21/150 (14.0%) / 17/150 (11.3%) / 25/150 (16.7%)**。所以「跟上次不一樣」
> 本身不是任何東西的證據。
>
> **`toctou_hits=0` 不等於「已經修好」**，最可能只代表這次的 racer 沒搶贏。R1 只有在
> 綁定檢查從「路徑」搬到「file descriptor」（`O_NOFOLLOW|O_APPEND` 開一次、`fstat` 驗
> 那個 fd、全程同一個 fd append）之後才算修掉。再加一道路徑檢查是沒有用的——那只是把
> 窗口變窄，不是關掉。

The hit rate is wildly harness-dependent — 3.3% through 96.7% on byte-identical code.
Read the preconditions, not the percentage. Zero hits is not evidence of a fix.

---

### `probe-log-path-variants.sh` — 在日誌路徑上種各種物件

**驗什麼**：日誌路徑不是「正常自有一般檔」時的七種形狀：`dangling`（斷掉的 symlink）、
`fifo`、`socket`、`dir`、`chain`（多跳 symlink 到不存在的 target）、`chain_live`
（多跳到存在的檔）、`hardlink`。這是 `88e6611`（跟著預先種好的連結寫）與 `ca02eca`
兩個修復的直接證據來源。`hardlink` 那一列同時是 R2 結論的來源之一。

**怎麼跑**：`./test/residual-harness/probe-log-path-variants.sh`
（或指定：`… fifo hardlink`；換版本：`--brm /path/to/better-rm`）

**今天應該印什麼**（2026-08-20 實測）：七個 variant 全部 `VERDICT: SAFE`，每一個都出現
拒絕訊息（`refusal warning shown: yes`）、target 沒有被建立或被寫入、victim 有進垃圾桶、
`exit=0`、耗時 ~0.05s、FIFO 那一列的 `strays still blocked on the fifo: none`、
dangling 那一列第二次刪除後 target 仍然 `exists=no`。結尾
`RESULT: every planted shape was refused safely`。

**「沒有出現拒絕訊息」本身就算缺陷**（`DEFECT - NO REFUSAL`）。這條不是裝飾：七種形狀
沒有一種是合法日誌，而且它是唯一看得見 `trimmed` 半套修法的檢查——target 那幾項對它
完全沒反應。要驗這條真的會紅，就拿一個 trimmed build 去跑 `socket`（見上一節）。

需要 `timeout`（macOS 請 `brew install coreutils`），因為修復前 FIFO 那一種會永遠卡住。

---

### `probe-fifo-margin.sh` — FIFO 測試的 15 秒上限還剩多少餘裕

**驗什麼**：「日誌路徑是 FIFO 時停止記錄，而且不會卡住」那個測試用 `run_bounded 15`
圍住 better-rm。這支量綠路徑的實際耗時，回答「15 秒是寬鬆到不會誤報，還是剛好卡在
邊緣」。

**怎麼跑**：`./test/residual-harness/probe-fifo-margin.sh [次數]`（預設 20）

**今天應該印什麼**（2026-08-20，閒置）：`min≈0.044 median≈0.049 max≈0.054`，
`margin ≈ 14.95s（約 278x headroom）`。

**這是閒置機器上的數字。** R3 已經證明牆鐘斷言在負載下會翻紅，所以「餘裕很大」只在
同樣的負載條件下成立。

---

### `probe-run-bounded.sh` — 沒有控制終端時 `run_bounded` 還正確嗎

**驗什麼**：`run_bounded` 靠 `set -m` 把背景工作放進自己的 process group，逾時就
`kill -9 -$pid` 整組殺掉。這在有 tty 的互動 shell 上一定成立，在 CI runner 上不見得。
四個 case：狀態碼傳回、孫代行程卡在 FIFO 的 `open()` 要能逾時且**不留孤兒**、群組殺
不可能打到 suite 自己的 pgroup、逾時後 shell 的 job table 仍然乾淨。

裡面的 `run_bounded` 是**執行期從 repo 現行的 `test-better-rm.sh` 抽出來的**，不是複製
一份會走味的舊碼；抽不到就整支失敗。

**怎麼跑**：`./test/residual-harness/probe-run-bounded.sh`

**今天應該印什麼**：`tty on stdin/stdout = no`（正是要模擬的情境）、四個 check 全 OK、
case B elapsed ≈ 4.3s、`orphans left blocked in open() OK (0)`、
`RESULT: run_bounded behaves correctly with no controlling terminal.`

---

### `vacuity-log-path-tests.sh` — 那兩個新測試是不是空洞的

**驗什麼**：只破壞測試**自己的前提**（`mkfifo` → `touch`、`ln -s` → `touch`），
`better-rm` 完全不動。普通自有檔是合法日誌，拒絕訊息不會出現，所以那兩列必須紅。
兩列都紅 ＝ 斷言真的綁著；任何一列還綠 ＝ 那個測試量不到它宣稱在量的東西。

**怎麼跑**：`./test/residual-harness/vacuity-log-path-tests.sh`

**今天應該印什麼**：baseline `failed=0`，sabotage 之後**剛好 2 個失敗**，且失敗清單就是
FIFO 與斷掉 symlink 那兩列。

---

### `repeat-core.sh` — 同一份碼連跑 N 次

**驗什麼**：R3 的結論（「兩個 commit 都紅、檔案逐位元組相同 ＝ 負載相依，不是回歸」）
只有拿得出「同一份碼重複跑」的資料才講得出來。這支就是那個資料來源，順便檢查有沒有
留下 `better-rm` 的孤兒行程。

**怎麼跑**：`./test/residual-harness/repeat-core.sh [-n N] [--full]`
（`--full` 跑整套 `run-test-suites.sh` 而不只是核心 suite）

**今天應該印什麼**（2026-08-20 實測，N=5）：五次全部 `exit=0`、136/136、
每次 elapsed 約 23–24 秒（離散度 < 1 秒）、`stray better-rm processes … (none)`。

> ⚠️ **閒置全綠不代表沒有負載敏感的斷言**，只代表這台機器現在很閒。要重現 R3 請一邊
> 跑 12 個 spinner 一邊跑 `node test-hooks.js`——那條 1000ms 牆鐘斷言在 `test-hooks.js`
> 裡，不在核心 suite 裡，所以這支腳本**不會**重現 R3。

---

## 哪些數字是 harness-dependent（讀報告前先看這段）

| 數字 | 穩定嗎 |
|---|---|
| R1 的 TOCTOU 命中率 | **極不穩定。3.3%–96.7%，同一份程式碼。任何單一數字都只描述那一次的 harness。** 同一支 harness 同一台機器連跑三次也只有 11.3% / 14.0% / 16.7% |
| R3 的 1000ms 預算 | **負載相依。**閒置綠、12 spinner 下 3/3 紅，而且兩個 commit 對稱地紅。 |
| FIFO 路徑耗時 / 15s 餘裕 | 閒置時穩定（~0.05s），負載下沒量過。 |
| pin 的 GREEN/RED 判定 | 穩定。純 grep，跟負載無關。 |
| 突變的 CAUGHT / PIN-ONLY / NOT-CAUGHT 判定 | 穩定。 |
| `total=136` | 穩定（`edd22fd`）。哪天不是 136，先確認是不是有人加了測試。 |

---

## 這次移植過程中量出來的三件新事

移植不是純搬運：把即席量測寫成可重跑的形式時，有三件事跟現有記載對不上。**這三件都
沒有動 `KNOWN-RESIDUALS.md`**——要不要改那份文件是使用者的決定，這裡只記錄量到什麼。

1. **極限 4 的緩解措施在 NUL 種在檔尾時不成立。** `KNOWN-RESIDUALS.md` 說「git 會把該檔
   顯示成 binary，review 時很難不注意」。git 只看**前 8000 bytes**，而該文件是
   10,318 bytes，所以 NUL 附在檔尾時 `git diff --numstat` 印的是一般文字 diff
   （`4  24`），NUL 種在開頭才印 `-  -`。`pin-nul-evasion.sh` 兩種位置都量給你看。
2. **R2 的「整套照樣全綠」在 `edd22fd` 已不再逐字成立。** 刪掉 `[ -O ]` 現在會讓那個
   雙向釘紅（`5e295ef` 起釘子會 grep 活碼）。**R2 的實質沒變**——行為覆蓋率仍然是零，
   所以 `mutants-log-binding.sh` 把它判成 `PIN-ONLY` 而不是 `CAUGHT`。
3. **「只擋 FIFO」的半套修法整套 136 個測試都抓不到（`trimmed` mutant）。**
   唯一可觀察的差別是 socket 日誌被靜默接受。也就是 FIFO 那個測試釘的是「不會卡住」，
   不是「必須是一般檔」。這是既有缺口，這次只記錄、沒有補測試。

Three things measured during the port that do not match the existing record: the
limit-4 mitigation fails for a NUL past byte 8000 (git only inspects the first 8000);
R2's "the whole suite stays green" is no longer literally true at `edd22fd` (the pin
itself now greps the live clause — behavioural coverage is still zero, hence the
`PIN-ONLY` verdict); and a "reject only FIFOs" trimmed fix escapes all 136 tests, its
only observable effect being a silently accepted socket log.

---

## DEDUPED — 哪些來源腳本被合併掉了

scratchpad 裡有 22 支，這裡是 11 支。沒有東西被丟掉，只是不再出貨近乎重複的版本。

| 出貨 | 來源 | 為什麼這樣合 |
|---|---|---|
| `pin-redproof.sh` | `redproof.sh` | 一對一 |
| `pin-anchor-uniqueness.sh` | `uniqueness.sh` ＋ `sameline.sh` ＋ `anchor-uniqueness.sh` | 三支各有一份幾乎相同的「刪除矩陣」，重疊的部分只留一次；三支各自獨有的 case（程式碼圍籬內的重複、同行三份、只刪 R1 修法段落、locale 可攜性）全部保留 |
| `pin-comment-forms.sh` | `comment-probe.sh` | 一對一，另外補了極限 3 明列的九種「仍然綠」形狀（見下方 PORT NOTES） |
| `pin-nul-evasion.sh` | 無 | 極限 4 在 scratchpad 裡沒有腳本（當時是即席量的），這支是補寫的 |
| `probe-log-path-variants.sh` | `probe_variants.sh` ＋ `probe_dangling.sh` ＋ `probe_fifo.sh` ＋ `probe-dangling.sh` ＋ `probe-fifo.sh` | 五支做的是同一件事：在日誌路徑種一個物件然後刪一個檔。`probe_variants.sh` 是最完整的（六種形狀＋自動判定），所以以它為底，另外**補上一個 `dangling` variant**，並把兩支較弱版本各自獨有的檢查併進來：`probe-dangling.sh` 的**第二次刪除**、`probe-fifo.sh` 的**孤兒行程列表**。兩支較弱版本沒有隔離 `HOME`，這是不出貨它們的主因 |
| `probe-toctou-rate.sh` | `probe_toctou.sh` | 一對一。`probes/toctou/racer.sh` 是它用 heredoc 產生的，不是獨立來源檔 |
| `probe-fifo-margin.sh` | `measure_fifo_margin.sh` | 一對一 |
| `probe-run-bounded.sh` | `portability_run_bounded.sh` ＋ `proto-bounded.sh` | 後者是前者的原型，前者多了「無控制終端」與 pgid／孤兒檢查。以前者為底，併入後者的 job-table 檢查。`proto/hang.sh` 是 heredoc 產生的 |
| `mutants-log-binding.sh` | `build_mutants.sh` ＋ `run_mutant_suites.sh` ＋ `mutate.sh` | 前兩支是「造突變」與「跑突變」的兩半，本來就得一起用；`mutate.sh` 是另一輪的兩個突變（`regular`、`occupancy`），併成同一張突變表 |
| `vacuity-log-path-tests.sh` | `vacuity.sh` | 一對一 |
| `repeat-core.sh` | `repeat_core.sh` ＋ `run_full.sh` | `run_full.sh` 只是「用假 HOME 跑整套 runner」，變成 `--full` 旗標 |

---

## PORT NOTES — 移植時改了什麼

所有 22 支原版都**寫死了 scratchpad 的絕對路徑**，而且其中 11 支寫死的是一個**已經不
存在**的第二個 scratchpad（`…/gacc2/better-rm`）。原樣搬進 repo 全部都是死碼。每一支
都套了同一個模式：

- repo 從 `${BASH_SOURCE[0]}` 推導 ＋ 驗證，不寫死路徑；
- 工作區 `mktemp -d`，EXIT/INT/TERM 清理；
- 落在 repo 內就拒跑；
- `HOME` / `TRASH_DIR` / `BETTER_RM_STATE_DIR` / `XDG_STATE_HOME` / `TMPDIR` / cwd
  全部指進工作區；
- `sed -i ''` → `perl -i`（BSD-only → 兩平台通用）；
- python3 → perl `Time::HiRes`（不假設有 python3）；
- 原版對每個突變複製一次整個 repo（4–6 份），改成單一副本 ＋ 快照還原，最後驗
  byte-identity。

**超出機械改寫的三支**：

1. `probe-log-path-variants.sh` — 五支合一，並補上原本只存在於較弱版本的兩個檢查
   （第二次刪除、孤兒行程），以及一個原本 `probe_variants.sh` 沒有的 `dangling` variant。
   另外把「沒有出現拒絕訊息」升級成缺陷判定：原版只看 target 有沒有被建立／被寫入，
   而那組檢查**看不見** `trimmed` 半套修法。新判定已 red-proof（對 trimmed build 的
   socket 會紅，對出貨版七種形狀全綠）。
2. `pin-comment-forms.sh` — 原版只驗「行首註解那一種現在會紅」。極限 3 明列的九種
   **仍然綠**的形狀在 scratchpad 裡沒有對應腳本（當時是即席量的），這次照文件列舉的
   形狀補寫成 `OPEN-1`…`OPEN-9`。**九種全部重現為 GREEN**，與文件一致。
3. `pin-nul-evasion.sh` — 全新，極限 4 原本沒有腳本。寫的過程中量出文件的緩解措施
   有誤（見上方該節第 2 點）。

另外，底座新增了兩道原版沒有的自我檢查，因為原版有一個真實風險：一個打空的取代會讓
探針印出「GREEN ＝ 洞還開著」，而其實它什麼都沒改。

- `hs_assert_changed` — 突變必須真的改到檔案；
- `hs_assert_parses` — 突變後 `bash -n` / `node --check` 必須還過，否則「pin 還是綠的」
  可能只是因為檔案已經壞掉。

---

## 沒有被移植的東西

- `mA_symlink/`、`mB_owner/`、`mC_nlink/`、`mD_trimmed/`、`vac/`、`work/`、`mut*/`、
  `pristine/`、`uniq2/`、`sameline/`、`comment-probe/`、`pin-redproof/`、`anchor-uniq/`
  ——這些是**被突變過的 repo 副本**，不是 harness，可以用上面的腳本重新產生。
- `probes/toctou/racer.sh`、`proto/hang.sh` ——由 heredoc 產生的中間檔。
- `*.log`、`brm.mut1`、`mut.tmp`、`better-rm.HEAD`、`brm_gap.json`、`commit-msg.txt`
  ——某一次執行的產出，不是可重跑的東西。
