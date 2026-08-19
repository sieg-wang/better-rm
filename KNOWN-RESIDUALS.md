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
   一個孤零零的 `O_NOFOLLOW`（甚至塞在 HTML 註解裡），照樣綠。**釘子看得到字串，
   看不到位置與上下文。**
3. **程式碼那一半原本也可以被「註解掉而不是刪掉」繞過**——這一個已修：現在兩個
   程式碼 anchor 都先濾掉註解行才比對。修之前，把 `[ -O ]` 那行加個 `#` 就能讓
   「有牙齒的那一半」失效，而註解掉一行是再普通不過的編輯。

還有一個已知的假陽性：對 `[ -O ]` 做語意不變的改寫（例如換個等價寫法）會讓釘子
變紅，而診斷訊息會說「已不在活碼裡」——方向是安全的（寧可誤報），但那句話當下
是錯的。看到它請直接看程式碼，別信訊息字面。

Stated limits, all measured on 2026-08-19: a prose pin catches deletion but not
in-place negation (1), and not wholesale removal of the reasoning as long as the
token survives anywhere in the file (2). The code-side half was ALSO defeatable by
commenting the line out rather than deleting it — now fixed by filtering comment
lines before matching (3). One known false positive: a semantics-preserving rewrite
of the `[ -O ]` clause trips the pin with a diagnostic that is then literally wrong.

---

## R1 — 日誌綁定檢查是 TOCTOU-racy（same-UID）

`log_file_is_bound()` 驗的是**路徑**：`[ -L ]` / `[ -f ]` / `[ -O ]` / link 數
都對路徑做，通過之後 `log_deletion` 才用同一個路徑去 append。兩者之間有窗口，
並行行程可以把 symlink 換進來，append 就跟著走過去。

**實測：150 次迭代命中 43 次**（2026-08-18，同 UID racer）。

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

**為什麼沒補測試**：要構造攻擊需要一個**別的 UID 擁有的檔案**放在使用者自有的
0700 目錄裡，而不用 root 就沒辦法 chown 給另一個 UID。這不是「還沒寫」，是
**寫不出來**。

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
