# Known residuals — measured, deliberately unfixed

這個檔案是給**下一個審查者**看的，不是給使用者看的。

下面三項都經過實測、都是既有殘留、都刻意沒修。如果一次 review 又「發現」它們，
那是重複勞動——先讀這裡的理由，再決定要不要推翻它。

每一項都有 `test-better-rm.sh` 裡的一個測試釘著，而且那個測試是**雙向**的：
文字不見了會紅，**底下的程式碼事實變了也會紅**。第二半是重點——它逼著「修好了
卻忘了刪這段文字」變成一次失敗，而不是一段悄悄過期的謊。

This file is for the **next reviewer**, not for users. All three items below are
measured, pre-existing, and deliberately unfixed. A review that "finds" them again
is repeating work already done — read the reasoning first, then decide whether to
overturn it. Each is pinned by a test in `test-better-rm.sh`, and the pin is
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
   locale。少任一個都會紅（同攻擊無 NUL → 紅；有 NUL 但 UTF-8 locale → 紅），
   而且 git 會把該檔顯示成 binary，review 時很難不注意。
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
