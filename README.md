# better-rm

給你一個更好、更安全的 `rm` 命令

## 專案簡介

`better-rm` 是一個 Linux/Unix/macOS 下的 `rm` 命令替代方案，主要目的是防止誤刪重要檔案與目錄。與傳統的 `rm` 命令不同，`better-rm` 不會永久刪除檔案，而是將檔案移至垃圾桶目錄，讓你有機會救回誤刪的檔案。

### 主要特色

- 🛡️ **安全保護**：防止刪除重要的系統目錄和專案目錄（如 `/`, `/home`, `/usr`, `.git` 等）
- ♻️ **垃圾桶機制**：將檔案移至垃圾桶而非永久刪除
- 📁 **保留目錄結構**：在垃圾桶中維持原始的完整路徑結構，方便日後還原
- 🔧 **完整相容**：支援所有常見的 `rm` 參數（`-r`, `-f`, `-i`, `-v` 等）
- ⚙️ **可自訂**：透過環境變數自訂垃圾桶與狀態資料位置
- 🎨 **友善介面**：彩色輸出，清楚顯示操作狀態

## 安裝方式

### 快速安裝（推薦）⚡

只需一行命令即可自動安裝：

```bash
curl -sSL https://raw.githubusercontent.com/doggy8088/better-rm/main/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/doggy8088/better-rm/main/install.sh | bash
```

安裝腳本會自動：
- ✅ 下載 better-rm 到 `~/.better-rm` 目錄
- ✅ 偵測你的 shell (bash/zsh) 並設定別名
- ✅ 加入 `alias rm='~/.better-rm/better-rm'` 到你的 shell 設定檔
- ✅ 提供清楚的後續步驟說明

安裝完成後，執行以下命令啟用：

```bash
source ~/.bashrc  # 如果使用 bash
# 或
source ~/.zshrc   # 如果使用 zsh
```

驗證安裝：

```bash
rm --version
```

---

### 方法一：手動使用別名

這種方法最安全，不會覆蓋系統原生的 `rm` 命令，需要時仍可使用 `/bin/rm` 存取原始命令。

1. 複製專案到本地目錄：

```bash
git clone https://github.com/doggy8088/better-rm.git ~/.better-rm
```

2. 設定別名，在 `~/.bashrc` 或 `~/.zshrc` 中加入以下內容：

```bash
# 使用 better-rm 替代 rm 命令
alias rm='~/.better-rm/better-rm'
```

3. 重新載入設定檔：

```bash
source ~/.bashrc  # 或 source ~/.zshrc
```

4. 驗證安裝：

```bash
rm --version
```

應該會看到 `better-rm 1.5.0` 的版本資訊。

**提示**：如果需要使用系統原生的 `rm` 命令，可以使用完整路徑 `/bin/rm` 或用反斜線 `\rm`。

### 方法二：手動複製到 PATH 目錄

如果你想讓 `better-rm` 可以直接執行（不只是透過 `rm` 別名），可以將它複製到 PATH 目錄：

```bash
# 下載專案
git clone https://github.com/doggy8088/better-rm.git
cd better-rm

# 複製到 /usr/local/bin（需要 sudo 權限）
sudo cp better-rm /usr/local/bin/
sudo chmod +x /usr/local/bin/better-rm

# 或複製到使用者的 bin 目錄（不需要 sudo）
mkdir -p ~/bin
cp better-rm ~/bin/
chmod +x ~/bin/better-rm

# 確保 ~/bin 在 PATH 中（在 ~/.bashrc 或 ~/.zshrc 加入）
export PATH="$HOME/bin:$PATH"
```

然後可以選擇性設定別名：

```bash
# 在 ~/.bashrc 或 ~/.zshrc 中加入
alias rm='better-rm'
```

重新載入設定檔：

```bash
source ~/.bashrc  # 或 source ~/.zshrc
```

## 使用方式

### 基本語法

```bash
rm [選項] [檔案或目錄...]
```

### 支援的選項

| 選項 | 說明 |
|------|------|
| `-r`, `-R`, `--recursive` | 遞迴刪除目錄及其內容 |
| `-f`, `--force` | 強制刪除，忽略不存在的檔案，不提示 |
| `-i` | 每次刪除前提示確認 |
| `-I` | 刪除超過三個檔案或遞迴刪除前提示一次 |
| `-v`, `--verbose` | 顯示詳細操作過程 |
| `--` | 選項終止符：其後的引數一律視為檔名，即使名稱以破折號開頭。刪除可以接多個檔名；`--restore` 只接受一個，多出來的引數會被拒絕 |
| `--help` | 顯示說明訊息 |
| `--version` | 顯示版本資訊 |

### 使用範例

#### 刪除單一檔案

```bash
rm file.txt
```

#### 刪除目錄

```bash
rm -r directory/
```

#### 強制刪除（不提示）

```bash
rm -rf old_project/
```

#### 互動式刪除（每次都會詢問）

```bash
rm -i important_file.txt
```

#### 顯示詳細過程

```bash
rm -rv temp_folder/
```

#### 刪除名稱以破折號開頭的檔案

```bash
rm -- -dash.txt
```

刪除時，`--` 之後的每一個引數都是檔名。沒有 `--` 的話 `-dash.txt` 會被當成選項而被拒絕，這與 `rm(1)` 一致；還原時同樣要寫 `rm --restore -- -dash.txt`。

兩邊的範圍不一樣：刪除可以接任意多個檔名，`--restore` 只還原一個，因此 `rm --restore -- <檔案>` 後面再多出任何引數都會被拒絕（結束碼 1，不動任何檔案）。這是刻意的——多出來的引數若被當成旗標，`rm --restore -- victim.txt -f` 就會無提示地覆蓋目的地而且不留垃圾桶紀錄。要強制覆蓋請把旗標寫在前面：`rm -f --restore -- <檔案>`。

#### 使用自訂垃圾桶目錄

```bash
TRASH_DIR=/tmp/my-trash rm file.txt
```

## 垃圾桶機制

### 預設位置

垃圾桶預設位於 `~/.Trash` 目錄。

### 目錄結構保留

當你刪除一個檔案時，`better-rm` 會在垃圾桶中保留原始的完整路徑結構。

**範例：**

如果你刪除 `/home/user/projects/myapp/src/main.js`，該檔案會被移動到：

```
~/.Trash/home/user/projects/myapp/src/main.js
```

這樣做的好處：
- 可以清楚知道檔案原本的位置
- 方便日後開發還原功能
- 避免不同路徑下同名檔案的衝突

### 檔案名稱格式

從 v1.1.0 開始，垃圾桶中的檔案名稱會自動加上時間戳記和內容雜湊值：

```
原始檔案: file.txt
垃圾桶中: file.txt__20251209_143052_123456789__e59ff97941044f85df5297e1c302d260
格式說明: filename__YYYYMMDD_HHMMSS_NNNNNNNNN__hash
```

這樣的設計有以下好處：
- 時間戳記包含奈秒精度，避免快速刪除時的檔名衝突
- 內容雜湊值可用於識別檔案內容，方便重複檔案的管理
- 可追蹤檔案的刪除時間

> ⚠️ 雜湊值是**在搬移之前**算的，用途是辨識與命名，不是垃圾桶內容的完整性證明。
> 若物件在「算完雜湊」與「實際搬移」之間被改寫（同一個 inode 被寫入新內容、或目錄
> 樹裡多了／少了檔案），本工具的 inode 檢查抓不到這種變化，日誌與垃圾桶檔名裡的
> 雜湊就會描述舊的內容。要驗證垃圾桶裡的東西，請直接對垃圾桶中的項目重算雜湊。

### 刪除日誌

`better-rm` 會在狀態目錄中維護 `deletion.log`，記錄所有刪除操作。預設狀態目錄為 `~/.local/state/better-rm`；若設定了絕對路徑的 `XDG_STATE_HOME`，則使用 `$XDG_STATE_HOME/better-rm`：

```bash
# 查看刪除日誌
cat ~/.local/state/better-rm/deletion.log
```

從舊版本升級時，`--restore` 仍會在新日誌找不到符合項目後讀取 `$TRASH_DIR/.deletion_log`。新刪除操作只會寫入新的狀態目錄，不會搬移或刪除舊日誌。

日誌格式：
```
TIMESTAMP | v2 | ORIGINAL_PATH | TRASH_PATH | HASH | FILE_TYPE
```

`v2` 標記代表兩個路徑欄位是轉義過的：`\\` 反斜線、`\p` 直線 `|`、`\n` 換行、`\r` 歸位。因此含有 `|` 或換行的合法檔名也能被正確記錄與還原。沒有 `v2` 標記的紀錄是升級前寫下的舊版 5 欄格式（`TIMESTAMP | ORIGINAL_PATH | TRASH_PATH | HASH | FILE_TYPE`），`--restore` 仍可讀取。

範例：
```
20251209_084530_429345278 | v2 | /home/user/file.txt | /home/user/.Trash/.../file.txt__...__hash | d6eb320... | file
20251209_084547_505346836 | v2 | /home/user/mydir | /home/user/.Trash/.../mydir__...__hash | c55e1b8... | directory
20251209_084551_118273540 | v2 | /home/user/a\pb.txt | /home/user/.Trash/.../a\pb.txt__...__hash | 4b1e77f... | file
```

這個日誌可以幫助你：
- 追蹤所有刪除的檔案
- 找出特定檔案的刪除時間
- 確認檔案在垃圾桶中的位置
- 根據內容雜湊值找出重複的檔案

### 自訂垃圾桶位置

你可以透過 `TRASH_DIR` 環境變數來自訂垃圾桶位置：

```bash
# 暫時設定（單次使用）
TRASH_DIR=/tmp/trash rm file.txt

# 永久設定（在 ~/.bashrc 或 ~/.zshrc 中加入）
export TRASH_DIR="$HOME/MyTrash"
```

### 自訂狀態與日誌位置

你可以透過 `BETTER_RM_STATE_DIR` 自訂狀態目錄。此設定的優先順序高於 `XDG_STATE_HOME`：

```bash
# 暫時設定（單次使用）
BETTER_RM_STATE_DIR=/tmp/better-rm-state rm file.txt

# 永久設定（在 ~/.bashrc 或 ~/.zshrc 中加入）
export BETTER_RM_STATE_DIR="$HOME/.local/state/better-rm"
```

日誌包含原始路徑與垃圾桶路徑。新建立的狀態目錄使用 `0700` 權限，新建立的日誌使用 `0600` 權限。

## 受保護的目錄

為了防止災難性的誤刪，`better-rm` 會拒絕刪除以下重要目錄：

### 系統目錄

- `/` - 根目錄
- `/bin` - 系統二進位檔案
- `/boot` - 開機相關檔案
- `/dev` - 裝置檔案
- `/etc` - 系統設定檔
- `/home` - 使用者主目錄根目錄
- `/lib`, `/lib64` - 系統函式庫
- `/mnt` 與其第一層掛載根目錄 - 掛載磁碟（例如 WSL 的 `/mnt/c`、`/mnt/d`、`/mnt/wsl`、`/mnt/wslg`）
- `/opt` - 第三方軟體
- `/proc` - 程序資訊
- `/root` - root 使用者的家目錄
- `/sbin` - 系統管理二進位檔案
- `/sys` - 系統資訊
- `/usr` - 使用者程式
- `/var` - 變動資料

### macOS 系統目錄

- `/Applications` - 應用程式目錄（使用者可寫，不需要 root 就能刪光）
- `/Library` - 系統層級的資源庫
- `/Network` - 網路掛載點根目錄
- `/System` - 作業系統本體
- `/System/Volumes` 與其第一層掛載根目錄 - 現代 Mac 掛載自己那幾顆 APFS 卷宗的地方（`Data`、`Preboot`、`VM`、`Update`…）
- `/Users` - 使用者主目錄根目錄
- `/Volumes` 與其第一層掛載根目錄 - 掛載磁碟（外接碟、Time Machine、網路共享，例如 `/Volumes/Backup`）
- `/cores` - 核心傾印檔目錄
- `/private` - `/etc`、`/tmp`、`/var` 的實體位置

### 使用者目錄

- `~` 或 `$HOME` - 你的家目錄（整個目錄）

### 專案目錄

- `.git` - Git 版本控制目錄（任何位置的 .git 目錄），**以及它底下的一切**

`.git` 內部的路徑與 `.git` 本身一樣不可還原：`rm -rf .git/objects` 毀掉的是整個倉庫。
因此 `.git` 是以「路徑元件」認定的——`.git/objects`、`.git/refs`、`.git/index.lock`
都會被拒絕，`/bin/rm` 這道 hook 守著的 agent 路徑也是同一套判定。`.gitignore`、
`.github/workflows`、`vendor.git/objects` 這類名字裡有 `.git` 但元件不同的路徑不受影響。

這條規則會擋掉一件正當的事：git 操作中斷後手動清 `.git/index.lock`。方向是刻意選的
——擋過頭只是不方便，擋不夠丟的是資料。真的要清的時候用 `/bin/rm -f .git/index.lock`
（不經過本工具，因此也沒有垃圾桶副本）。

`/mnt` 的保護只涵蓋掛載根本身；仍可正常移除 `/mnt/c/project/tmp` 等掛載磁碟內的項目。
WSL 可透過 `/etc/wsl.conf` 更改 Windows 磁碟的 automount root；非預設位置不在本規則的保護範圍內。
`/Volumes` 是 macOS 的對應物，走同一段程式：`/Volumes` 與 `/Volumes/<磁碟>` 會被拒絕，
`/Volumes/Backup/old.log` 這類掛載磁碟內的項目仍可正常移除。`/System/Volumes` 是第三個掛載
父目錄，同一段程式：`/System/Volumes/Data`、`/System/Volumes/Preboot` 這一層會被拒絕。

### macOS firmlink：`/System/Volumes/Data/…` 與根目錄拼寫是同一個東西

macOS 用 firmlink 把資料卷宗接進根目錄，所以 `/Users/you` 與 `/System/Volumes/Data/Users/you`
是同一個 device、同一個 inode（`stat -f '%d:%i'` 兩邊一模一樣），`/Applications` 與
`/System/Volumes/Data/Applications` 也是。firmlink **不是**符號連結：`readlink -f` 兩個方向
都把路徑原樣送回來，沒有任何正規化會讓兩種拼寫碰面。因此保護清單會先把
`/System/Volumes/Data/` 這個前綴換掉再比對——`rm -rf /System/Volumes/Data/Users/you`
與 `rm -rf ~` 得到同一個拒絕。

- 判準不是「路徑存在」：`/System/Volumes/Data/Users/<還沒建立的名字>` 一樣被拒絕。
- 對應之後仍是逐條完全比對，不是前綴：`/System/Volumes/Data/Users/you/project` 照舊可刪。
- 前綴必須整段對齊：`/System/Volumes/DataDrive/...` 不會被當成 Data 卷宗。
- 侷限：這是拼寫上的對應，不是身分證明。資料卷宗上沒有的東西（例如
  `/System/Volumes/Data/usr`）會被對應成 `/usr` 而一併拒絕，方向是安全的那一邊；反過來，
  bind mount、hardlink 目錄之類「同一顆 inode、兩種拼寫」不在這條規則涵蓋範圍內。

清單其餘各項以完全相同的路徑比對，保護的是那個目錄本身而非其內容：`/Applications/Xcode.app`、
`/Library/Caches/foo` 這類目錄內的項目仍可正常移除。`/private` 同樣只涵蓋 `/private` 本身；
macOS 的 `/etc`、`/var` 是指向 `/private/etc`、`/private/var` 的符號連結，以實體路徑書寫
（`rm -rf /private/etc`）不在保護範圍內。

## Coding agent hooks

本專案提供共用的 `PreToolUse` 防護程式，讓支援 hooks 的 coding agent 在執行
`rm` 或 `rmdir` 前檢查目標路徑。下列專案層級設定會自動載入同一支程式：

| Coding agent | 設定檔 |
|---|---|
| Claude Code | `.claude/settings.json` |
| Codex | `.codex/hooks.json` |
| GitHub Copilot CLI／cloud agent | `.github/hooks/better-rm.json` |
| Antigravity CLI／2.0 | `.agents/hooks.json` |
| Qoder | `.qoder/settings.json` |
| Pi | `.omp/hooks/pre/protect-important-paths.ts` (native) / `.pi/hooks.json` (JSON) |
| Cursor | `.cursor/hooks.json` |
| OpenCode | `.opencode/plugins/protect-important-paths.ts` |
| Grok Build | `.grok/hooks/better-rm.json` |

### 無法靜態判定的命令字會被當成 `rm`（含少量誤擋）

命令字要展開後才知道是什麼時（`$CMD`、`$( … )`、反引號 —— 除了單引號之外，加不加
雙引號都一樣），hook 無法在執行前知道它是不是 `rm`，因此一律以最壞情況處理：
把它的操作對象當成刪除目標檢查。`CMD=rm; $CMD -rf /` 這類繞道因此擋得住，
**代價是有一類合法命令會被誤擋**。

**判定規則**（下表每一列都是實際跑過 hook 量到的結果）：
命令字無法靜態解析時，逐一檢查它的操作對象；以 `-` 開頭的字視為選項並略過；
只要剩下的操作對象中有任何一個是**動態的**（任何展開都折算成最壞情況 `/`）
或是**靜態的受保護路徑**，就會被拒絕。

反引號有一個特例：**反引號內容含有空白**時會被切成多個字，帶著結束反引號的那個
片段本身就是動態操作對象，因此**不論有沒有其他操作對象都會被拒絕**（連完全沒有
操作對象的 `` `command -v ls` `` 也一樣）。

| 現在會被擋（以前允許） | 為什麼 |
|---|---|
| `$(which docker) run -v $(pwd):/work img ls` | `$(pwd):/work` 是獨立的動態操作對象 |
| `"$(which docker)" run -v $(pwd):/work img ls` | **雙引號不會豁免**，只有單引號會 |
| `$(brew --prefix)/bin/rg "$PATTERN" src/` | `"$PATTERN"` 是獨立的動態操作對象 |
| `$(which git) -C $(pwd) status` | `$(pwd)` 與 `-C` 分開寫 → 是操作對象 |
| `$(which cat) $HOME/.zshrc` | `$HOME/…` 是動態的 |
| `$(which echo) $USER` | 任何展開都折算成 `/` |
| `$(which echo) /etc` | **操作對象不需要含展開**，靜態受保護路徑一樣擋 |
| `$(which echo) ~` | 裸 `~` 就是受保護的家目錄本身 |
| `` `which git` status ``、`` `command -v ls` `` | 反引號內含空白 → 無條件拒絕 |

| 仍然允許 | 為什麼 |
|---|---|
| `docker run -v $(pwd):/work img ls` | 執行檔是靜態的，整條規則不啟動 |
| `$(command -v python3) ./build.py` | 操作對象是靜態且未受保護的路徑 |
| `$(which make) -j$(nproc) all` | 動態值**緊接**在選項後（同一個字）→ 視為選項 |
| `$(which git) -C$(pwd) status` | 同上；寫成 `-C $(pwd)` 分開就會被擋 |
| `$(which cat) '$HOME/.zshrc'` | 單引號 → 是字面字串，不是展開 |
| `$(which cat) ~/.zshrc` | `~/…` 展開後不是受保護路徑（裸 `~` 才是） |
| `` `pwd` status `` | 反引號內沒有空白 → 不會多切出動態片段 |
| `cd $(git rev-parse --show-toplevel)` | `$( )` 不在執行檔位置 |

**發生頻率：不算罕見。** `$(which X) "$ARG"` 是很常見的寫法；本次修改的覆審者
在審查過程中自己就踩到兩次。請當成日常會遇到的事，而不是偶爾。

**繞開方式**：直接寫命令名（`docker run …`）、把動態值緊接在選項後（`-j$(nproc)`），
或用單引號。被擋時會顯示明確的拒絕訊息與它拒絕的路徑，不會靜默失敗。

預設保護範圍與 `better-rm` 相同：系統根目錄、使用者家目錄，以及任何位置的
`.git` 目錄。若要加入其他重要目錄，請以平台的 PATH 分隔字元設定
`BETTER_RM_PROTECTED_DIRS`：

```bash
export BETTER_RM_PROTECTED_DIRS="/srv/data:/workspace/secrets"
```

hooks 執行時需要 `node` 可用。Codex 還會要求使用者透過 `/hooks` 審閱並信任
專案 hook；其他代理也可能依各自的安全設定要求確認。

### 自動安裝 Coding Agent hooks / Automatic Coding Agent hook installation

`install-hooks.sh` 目前已支援下列 Agent：`claude`、`codex`、`cursor`、`copilot`、`antigravity`、`qoder`、`pi`、`opencode`、`grok`。

推薦用一行指令（自動抓取最新 Release）：

```bash
curl -sSL https://github.com/doggy8088/better-rm/releases/latest/download/install-hooks.sh | bash -s -- -a claude
```

如果有需要全域安裝 Claude 設定：

```bash
curl -sSL https://github.com/doggy8088/better-rm/releases/latest/download/install-hooks.sh | bash -s -- -a claude --global
```

使用 `-a` 或 `--agent` 指定 Agent；預設會安裝到目前目錄所屬 Git 專案的對應設定檔：

```bash
# 安裝到目前 Git 專案 / Install into the current Git project
~/.better-rm/install-hooks.sh -a claude
~/.better-rm/install-hooks.sh --agent codex
~/.better-rm/install-hooks.sh --agent cursor
~/.better-rm/install-hooks.sh --agent copilot
~/.better-rm/install-hooks.sh --agent antigravity
~/.better-rm/install-hooks.sh --agent qoder
~/.better-rm/install-hooks.sh --agent pi
~/.better-rm/install-hooks.sh --agent opencode
~/.better-rm/install-hooks.sh --agent grok

# 安裝到 Claude Code 全域設定 / Install into Claude Code global settings（僅此支援 --global）
~/.better-rm/install-hooks.sh --agent claude --global
```

專案模式可從 Git 儲存庫內的任何子目錄執行。`--global` 目前僅 Claude Code 支援；其他 Agent 僅可在專案模式。
Claude Code 的全域模式會寫入
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`，且不要求目前目錄是 Git
儲存庫。其他 Agent 會寫入專案根目錄對應設定檔：`.claude/settings.json`（claude）、`.codex/hooks.json`（codex）、`.cursor/hooks.json`（cursor）、`.github/hooks/better-rm.json`（copilot）、`.agents/hooks.json`（antigravity）、`.qoder/settings.json`（qoder）、`.pi/hooks.json`（pi）、`.opencode/plugins/protect-important-paths.ts`（opencode）與`.grok/hooks/better-rm.json`（grok）。
安裝程式會保留其他設定與 hooks，只新增或更新目標 hook；修改既有檔案前會建立時間戳備份，重複執行時不會加入重複項目或重寫已是最新狀態的檔案。

自動安裝的 hook 會放在設定檔同目錄，例如
`.claude/settings.json` 對應 `.claude/protect-important-paths.js`，
`.codex/hooks.json` 對應 `.codex/protect-important-paths.js`。  
建議不再依賴 `install-hooks.sh` 執行路徑，已安裝的 hook 僅依賴各 Agent 的
設定目錄中對應的 `protect-important-paths.js`，若移動或刪除該目錄需重跑安裝程式。
`install.sh` 與 `install-hooks.sh` 是分開的步驟，不會在安裝 `rm` 別名時自動修改
Agent 設定。變更設定後，可能需要重新啟動相應 Agent 或開啟新的 session。

下方手動設定範例仍適用於 hook 檔案已提交在目標專案中的情況；其中
`git rev-parse --show-toplevel` 會從該專案載入 hook。對於 OpenCode，請參考下方 plugin 範例。

### 各個 Coding Agent 的安裝與設定說明 / Detailed Agent Configurations

本專案支援將防護機制嵌入多種熱門的 AI Coding Agent。以下是為各代理設定 `PreToolUse` 的詳細說明：

#### 1. Claude Code
* **設定檔位置**：`.claude/settings.json`
* **設定內容**：
  ```json
  {
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"",
              "timeout": 5,
              "statusMessage": "Checking protected directories..."
            }
          ]
        }
      ]
    }
  }
  ```
* **說明**：Claude Code 在執行 `Bash` 工具前，會先呼叫此 hook 檢查指令是否包含刪除受保護目錄的指令。

#### 2. Codex
* **設定檔位置**：`.codex/hooks.json`
* **設定內容**：結構與 Claude Code 相同。
* **說明**：載入設定檔後，請在 Codex 介面中執行 `/hooks` 來審閱並信任此專案 hook，以使防護生效。

#### 3. GitHub Copilot CLI / Cloud Agent
* **設定檔位置**：`.github/hooks/better-rm.json`
* **設定內容**：
  ```json
  {
    "version": 1,
    "hooks": {
      "preToolUse": [
        {
          "type": "command",
          "bash": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"",
          "powershell": "node \"$(git rev-parse --show-toplevel)\\hooks\\protect-important-paths.js\"",
          "matcher": "bash|powershell",
          "timeoutSec": 5
        }
      ]
    }
  }
  ```
* **說明**：Copilot 會依據作業系統選擇執行 `bash` 或 `powershell` 版指令。

#### 4. Antigravity CLI / Antigravity 2.0
* **設定檔位置**：`.agents/hooks.json`
* **設定內容**：
  ```json
  {
    "better-rm-protection": {
      "PreToolUse": [
        {
          "matcher": "run_command",
          "hooks": [
            {
              "type": "command",
              "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"",
              "timeout": 5
            }
          ]
        }
      ]
    }
  }
  ```
* **說明**：Antigravity 透過攔截 `run_command` 工具來防止對受保護目錄的刪除動作。若被阻擋會直接向 agent 回傳拒絕訊息。

#### 5. Qoder
* **設定檔位置**：`.qoder/settings.json`
* **設定內容**：
  ```json
  {
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\""
            }
          ]
        }
      ]
    }
  }
  ```

#### 6. Pi Coding Agent
Pi 支援兩種整合方式，您可以選擇其中一種：
* **方式 A：原生 TypeScript Hook (推薦)**
  * **路徑**：`.omp/hooks/pre/protect-important-paths.ts`
  * **內容**：
    ```typescript
    import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
    // @ts-ignore
    import { evaluate } from "../../../hooks/protect-important-paths";

    export default function hook(pi: HookAPI): void {
      pi.on("tool_call", async (event, ctx) => {
        if (event.toolName === "bash") {
          const command = event.input.command as string;
          const cwd = (ctx as any)?.cwd || process.cwd();

          const payload = {
            tool_input: { command },
            cwd
          };

          const result = evaluate(payload);
          if (result && result.hookSpecificOutput?.permissionDecision === "deny") {
            return {
              block: true,
              reason: result.hookSpecificOutput.permissionDecisionReason
            };
          }
        }
      });
    }
    ```
* **方式 B：JSON 設定檔 (透過社群擴充套件如 `pi-hooks`)**
  * **路徑**：`.pi/hooks.json`
  * **內容**：
    ```json
    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              {
                "type": "command",
                "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"",
                "timeout": 5,
                "statusMessage": "Checking protected directories..."
              }
            ]
          }
        ]
      }
    }
    ```

#### 7. Cursor
* **設定檔位置**：`.cursor/hooks.json`
* **設定內容**：
  ```json
  {
    "version": 1,
    "hooks": {
      "beforeShellExecution": [
        {
          "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"",
          "matcher": ".*"
        }
      ]
    }
  }
  ```
* **說明**：Cursor 在執行 `beforeShellExecution` 生命週期事件前會先執行此 hook。當判定為高風險時，回傳 `permission: "deny"` 將其完全阻擋。

#### 8. OpenCode
* **路徑**：`.opencode/plugins/protect-important-paths.ts`
* **補充**：`install-hooks.sh -a opencode` 會一併安裝共用 runtime 到專案 `hooks/protect-important-paths.js`，供插件在 `../../hooks/protect-important-paths` 匯入。
* **內容**：
  ```typescript
  import type { Plugin } from "@opencode-ai/plugin";
  // @ts-ignore
  import { evaluate } from "../../hooks/protect-important-paths";

  export const ProtectImportantPathsPlugin: Plugin = async (ctx) => {
    return {
      "tool.execute.before": async (input, output) => {
        if (input.tool === "bash") {
          const command = output.args.command;
          const cwd = (ctx as any)?.directory || process.cwd();

          const payload = {
            tool_input: { command },
            cwd
          };

          const result = evaluate(payload);
          if (result && result.hookSpecificOutput?.permissionDecision === "deny") {
            throw new Error(result.hookSpecificOutput.permissionDecisionReason);
          }
        }
      },
    };
  };

  export default ProtectImportantPathsPlugin;
  ```
* **說明**：OpenCode 會在啟動時自動載入此 TypeScript 插件。該插件會在執行 `bash` 工具前攔截指令並執行檢查，若判定為高風險刪除動作將拋出錯誤以阻止執行。

#### 9. Grok Build
* **設定檔位置**：`.grok/hooks/better-rm.json`
* **設定內容**：
  ```json
  {
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"",
              "timeout": 5
            }
          ]
        }
      ]
    }
  }
  ```
* **說明**：Grok Build 會讀取 `.grok/hooks/` 目錄下的所有 JSON 檔以載入 hooks。當偵測到危險指令時，本防護程式會回傳 `{"decision": "deny", "reason": "..."}` 供其阻擋指令的執行。請注意，專案層級的 hooks 首次執行時可能需要藉由 TUI 中的 `/hooks-trust` 或是帶有 `--trust` 參數啟動以取得授權。



這些 hooks 是額外防護欄，不是作業系統層級的安全邊界。目前只檢查 coding
agent 透過已支援 shell 工具送出的 `rm` 與 `rmdir` 命令；無法防止代理未攔截
的工具路徑、停用 hooks 後的操作，或使用者在代理外直接執行的命令。

### 保護機制

當你嘗試刪除受保護的目錄時，`better-rm` 會：

1. 顯示錯誤訊息
2. 拒絕執行刪除操作
3. 提示這是重要的系統或專案目錄

**範例：**

```bash
$ rm -rf /
錯誤 (Error): 拒絕刪除受保護的目錄: '/'
錯誤 (Error): Refused to remove protected directory: '/'
錯誤 (Error): 這是一個重要的系統目錄或專案目錄！
錯誤 (Error): This is a critical system or project directory!
```

## 清理垃圾桶

`better-rm` 目前不會自動清理垃圾桶，你可以手動清理：

### 檢視垃圾桶內容

```bash
ls -la ~/.Trash/
```

### 清空垃圾桶

```bash
# 使用系統原生的 rm 命令（請小心！）
/bin/rm -rf ~/.Trash/*
```

### 還原檔案 / Restore Files

`better-rm` 提供了自動與手動還原功能：

#### 1. 自動還原（推薦）
您可以使用 `--restore` 選項來將最後一次刪除的檔案或目錄還原至**目前資料夾**：

```bash
rm --restore LICENSE
```

- **名稱以破折號開頭時要用 `--`**：`rm --restore -- -dash.txt`，而且 `--` 之後只接受這一個路徑。與刪除端一樣，沒有 `--` 的破折號開頭引數會被視為「`--restore` 缺少引數」，以免把誤打的 `rm --restore -f` 默默當成要還原的檔名；`--` 之後再多出來的引數則直接被拒絕，因為那個位置的引數若被當成旗標，`rm --restore -- victim.txt -f` 會無提示地覆蓋目的地、而且不留垃圾桶紀錄。旗標寫在 `--restore` 前面（`rm -f --restore -- <檔案>`）照舊生效。
- **重名保護機制**：若目前資料夾已存在同名檔案或目錄，`better-rm` 會提示您是否確認覆蓋（`y/N`）。回答 `y` 與 `-f` 走的是同一條路——被覆蓋的那一個先進垃圾桶（見下）；回答 `n`（或直接按 Enter）則什麼都不做，目的地與垃圾桶項目都原封不動。
- **強制覆蓋**：如果您希望直接覆蓋而不顯示提示，可以加上 `-f` 參數：
  ```bash
  rm -f --restore LICENSE
  ```
- **覆蓋是以 rename 就位**：還原時，垃圾桶項目會先搬進一個本行程獨佔建立的暫存目錄，再用同一檔案系統內的一次 rename 就位；讓位已經在這之前完成，所以 rename 通常落在一個空的路徑上，過程中不存在「先把目的地刪掉」的步驟。您同意覆蓋時仍保留 `-f` 語意，因此讓位之後才被別的行程放上來的東西一樣會被原子取代。跨裝置的複製發生在暫存目錄裡，複製失敗時目的地完全沒被碰過。若目的地起初不存在、卻在還原途中才出現，未經覆蓋同意的還原會中止並把垃圾桶項目放回，而且那個目的地連一次 mv 的落點都不會是。
- **被覆蓋的目的地一律「移進垃圾桶」，不是被刪掉**：覆蓋等於刪除，所以佔著目的地的那個物件——不論是檔案、目錄、符號連結還是硬連結——都會先用本工具自己的垃圾桶機制保存起來（含刪除日誌紀錄），才輪到還原的項目就位。訊息會直接告訴您可以用 `rm --restore <名稱>` 取回它。`--restore` 全程不會執行任何遞迴刪除。
  - 佔著目的地的若是**符號連結**，被移走的是連結本身，不會跟隨到它指向的檔案。
  - 讓位一定在就位之前完成：讓不掉就整個中止（結束碼 `1`），垃圾桶項目放回原處，目的地一動也沒被動過。順序本身就是保證，不是「多半不會出事」。
  - 佔著目的地的若是**受保護的路徑**（例如 `.git`），它既不能被移進垃圾桶（那是原則性的拒絕），也不會改走就地讓位（那等於自己拆掉保護），因此還原直接中止，目的地保持原樣。
  - 這條路以前只走「rename 換不掉的目的地」（目的地是真目錄，或還原的項目是真目錄而目的地不是——`rename(目錄, 非目錄)` 是 `ENOTDIR`）。其餘情況倚賴 rename 由核心解除舊 inode 的連結，被蓋掉的那個檔案或連結就此消失、垃圾桶裡也沒有。
- **跨檔案系統**：垃圾桶與目的地不在同一個檔案系統時（外接碟、網路磁碟、另一個 APFS volume 搭配預設的 `$HOME/.Trash`），mv 會退化成「複製後刪除」，inode 必然改變。還原對這種情況有專門的驗收條件，不會因為 inode 變了就失敗。
- **垃圾桶那顆磁碟裝不下舊目的地時，改成「就地讓位」**：跨檔案系統的「移進垃圾桶」是一次完整複製，需要垃圾桶那一側真的有空間。因此在動手之前會先量（`df` 對上 `du`）：裝不下就不開始複製，改成在舊目的地旁邊獨佔建立一個 `<名稱>.better-rm-displaced-XXXXXX` 目錄，用同一檔案系統的一次 rename 把它移進去——rename 不需要任何空間，所以磁碟全滿也做得到。還原照常完成，兩份資料都在，訊息會印出舊目的地的完整新路徑。
  - 這種情況下的舊目的地**不在垃圾桶裡**，`rm --restore` 取不回它，請照訊息裡的路徑自行搬回或刪除。
  - 這是**降級的結果，不是乾淨的完成**：結束碼是 `2` 而不是 `0`，而且落腳處會同時印在 **stdout 與 stderr**——把 stderr 丟掉的呼叫端（`2>/dev/null`、CI step、包一層的腳本）一樣讀得到它得去收拾的那個路徑。stdout 那兩行不上色，是給程式讀的。
  - 走到這條路的不只是「垃圾桶那顆磁碟滿了」：一般的權限失敗（垃圾桶暫時寫不進去）而舊目的地依 inode 仍是那個已驗證的物件時，也會改走這裡；檔案、目錄、符號連結、硬連結、FIFO 都適用。
  - 受保護的路徑（例如 `.git`）不適用這條退路：那是原則性的拒絕，不是空間問題，還原會直接中止。
- **讓位進了垃圾桶、但刪除日誌沒寫成功時**，訊息會直說 `rm --restore` 取不回它，並要你到垃圾桶底下依原路徑尋找——因為那句 `rm --restore` 一定只會回「找不到刪除記錄」。
- **連續對同一個名字下 `rm --restore` 不會一路往回翻舊版本，而是在最新的兩個之間來回換**。`--restore` 取的是那個名字最新的一筆紀錄；而讓位（把佔著目的地的那一個移進垃圾桶）本身也會寫下一筆新的紀錄，於是被換下來的那個立刻變成「最新的一筆」，下一次 `--restore` 又把它取回來。實測：同一個檔名連續刪三次（內容 `V1`、`V2`、`V3`），接著連下五次 `rm -f --restore`，得到的是 `V3`、`V2`、`V3`、`V2`、`V3`，而 `V1` 從第一次還原之後就再也輪不到。
  - `V1` **沒有遺失**，它仍然完整躺在垃圾桶裡（本例是 `$TRASH_DIR/<原路徑>__<時間戳>__<hash>`），只是 `--restore` 這個入口到不了它。要拿回更舊的版本，請照下面的「手動還原」直接用 `mv` 從垃圾桶搬回，或先把目前資料夾裡的同名檔案改名再還原。
  - 這是「被覆蓋的目的地一律進垃圾桶」換來的代價：舊版的做法是把被覆蓋的那一個直接銷毀，所以連續 `--restore` 確實會一路往回翻——代價是每翻一次就永久毀掉一份。這一輪不改變這個行為，只是把它寫下來。
- **`--restore` 的結束碼**：
  - `0` — 還原完成，收尾也乾淨，沒有留下任何要你處理的東西。被移進垃圾桶的舊目的地不算（訊息會講，而且 `rm --restore` 取得回來）。
  - `1` — 還原沒有發生。錯誤訊息會直接指出任何無法放回原位的東西實際在哪裡；跨裝置複製若已經消耗掉垃圾桶來源，訊息會印出資料目前所在的暫存路徑。
  - `2` — **部分成功**：項目確實還原了，但留下了一個需要你處理的殘留物，而且它**不在垃圾桶裡**、`rm --restore` 取不回。目前有兩種：舊目的地走了「就地讓位」那條退路，或收尾（移除暫存目錄）沒能完成。殘留物的完整路徑會印出來，前者同時印在 stdout 與 stderr。這兩種情況絕不會回傳 `0`。

#### 2. 手動還原
由於被刪除的檔案在垃圾桶中仍保留了原始的完整路徑結構，您也可以使用系統原生的 `mv` 命令手動移回。
請至 `~/.local/state/better-rm/deletion.log`、舊版的 `$TRASH_DIR/.deletion_log` 或垃圾桶中找到您的檔案，然後手動移動：

```bash
# 手動還原範例
mv ~/.Trash/home/user/projects/myapp/file.txt__20251209_143052_123456789__hash /home/user/projects/myapp/file.txt
```

> ⚠️ 標有 `v2` 的紀錄中，兩個路徑欄位是**轉義過的**：`\\` 代表反斜線、`\p` 代表 `|`、`\n` 代表換行、`\r` 代表歸位。
> 若檔名含有這些字元，請勿直接把日誌裡的字串貼給 `mv`，要先還原轉義；
> 這種情況建議直接用 `rm --restore`，它會自動處理。

## 技術細節

### 相容性

- **作業系統**：Linux, macOS, Unix-like 系統
- **Shell**：Bash 4.0+
- **依賴**：基本的 Unix 工具（`mv`, `mkdir`, `readlink`/`realpath`）
- **`--restore` 另外硬性依賴 `mktemp`**：覆蓋流程建立在「只有本行程能建立、名稱不可預測的暫存目錄」之上，沒有它就沒有安全的還原路徑，因此找不到 `mktemp` 時 `--restore` 會直接中止並指名缺的是什麼。刪除功能不受影響。跨裝置的空間判斷另外會用到 `df` 與 `du`，量不到時一律照舊走「移入垃圾桶」。

### 限制

1. **跨檔案系統移動**：如果垃圾桶和原始檔案在不同的檔案系統（如不同的硬碟分割區），移動操作可能會比較慢。
2. **磁碟空間**：垃圾桶會佔用磁碟空間，需要定期清理。垃圾桶那一側空間不足時，跨檔案系統的刪除會在複製途中失敗，並可能在垃圾桶留下一份半成品複本（請自行清除）；`--restore` 的讓位步驟則會先量再決定，不會走進這個狀態。
3. **權限問題**：如果你沒有權限移動某個檔案，操作會失敗。

## 安全性考量 / Security Considerations

### ⚠️ 使用限制與風險 / Limitations and Risks

**重要：請在使用前充分了解以下限制**

1. **不是完整備份解決方案**
   - 垃圾桶機制僅提供基本的誤刪保護
   - 無法防護硬碟故障、系統故障、惡意軟體等風險
   - 重要資料必須有獨立的備份策略

2. **磁碟空間限制**
   - 垃圾桶會持續佔用磁碟空間
   - 可能導致磁碟空間不足的問題
   - 需要定期手動清理

3. **跨檔案系統限制**
   - 跨不同檔案系統的移動會較慢（需要複製而非移動）
   - 可能會遇到權限問題

4. **無保證性**
   - 本工具按「現況」提供，無任何保證
   - 作者不對任何資料遺失負責
   - 使用者需自行承擔風險

**Important: Please fully understand the following limitations before use**

1. **Not a Complete Backup Solution**
   - Trash mechanism only provides basic accidental deletion protection
   - Cannot protect against drive failure, system failure, malware, etc.
   - Important data must have an independent backup strategy

2. **Disk Space Limitation**
   - Trash continuously occupies disk space
   - May cause disk space shortage
   - Requires regular manual cleanup

3. **Cross-Filesystem Limitation**
   - Moving across different filesystems is slower (requires copy instead of move)
   - May encounter permission issues

4. **No Warranty**
   - This tool is provided "AS IS" without any warranty
   - Author is not responsible for any data loss
   - Users assume all risks

### 為什麼需要 better-rm？

在使用 AI 輔助編程工具（如 Claude Code, GitHub Copilot 等）時，AI 可能會建議執行一些危險的命令，例如：

```bash
rm -rf ~/  # 刪除整個家目錄！
rm -rf /   # 刪除整個系統！
```

這些命令一旦執行，後果不堪設想。`better-rm` 提供了一層防護網，即使不小心執行了這些命令，也不會造成永久性損害。

### 最佳實踐

1. **謹慎使用 `-f` 選項**：強制模式會跳過確認，建議先不加 `-f` 測試。
2. **定期清理垃圾桶**：避免佔用過多磁碟空間。
3. **重要檔案另外備份**：雖然有垃圾桶，但重要資料還是要有完整的備份策略。
4. **了解保護清單**：知道哪些目錄受到保護，避免驚訝。

## 疑難排解

### 問題：找不到 rm 命令 / Command not found

**解決方法：**

1. 如果您使用**快速安裝（推薦）**或**方法一（手動別名）**，可能是因為尚未重新載入 shell 設定檔。請執行以下命令以重新載入，或重啟終端機：
   ```bash
   source ~/.bashrc  # 如果使用 bash
   # 或
   source ~/.zshrc   # 如果使用 zsh
   ```

2. 如果您使用**方法二（複製到 PATH）**：
   - 請檢查 `~/bin` 或 `/usr/local/bin` 是否已加入 `PATH` 中（可以使用 `echo $PATH` 檢視）。
   - 確保已重新載入設定檔。

### 問題：提示權限被拒 / Permission denied

**解決方法：**

請確保 `better-rm` 檔案具備執行權限。依據您的安裝方式，執行對應的指令：

- 若使用**快速安裝**或**方法一（手動別名）**：
  ```bash
  chmod +x ~/.better-rm/better-rm
  ```
- 若使用**方法二（複製到 PATH）**：
  ```bash
  chmod +x ~/bin/better-rm
  # 或如果是複製到 /usr/local/bin（需要 sudo）
  sudo chmod +x /usr/local/bin/better-rm
  ```

### 問題：垃圾桶佔用太多空間

**解決方法：**

定期清理垃圾桶：
```bash
# 清理 30 天前的檔案
find ~/.Trash -mtime +30 -delete
```

### 問題：想要使用原生的 rm 命令

**解決方法：**

使用完整路徑呼叫系統原生的 rm：
```bash
/bin/rm file.txt
```

或用反斜線暫時繞過別名（bypass alias）：
```bash
\rm file.txt
```

## 未來計畫

- [x] 實作還原功能（`rm --restore`）
- [ ] 自動清理過期的垃圾檔案
- [ ] 提供垃圾桶管理介面
- [ ] 支援更多自訂保護規則
- [ ] 加入設定檔支援

## 測試

本專案包含完整的測試腳本，可在容器環境下測試所有功能：

```bash
# 執行測試
./test-better-rm.sh

# 在 Docker 容器中測試
docker run -v $(pwd):/app ubuntu:latest bash /app/test-better-rm.sh
```

測試涵蓋：
- ✅ 基本檔案與目錄刪除
- ✅ 特殊字元檔名處理
- ✅ 時間戳記與內容 Hash
- ✅ 刪除日誌功能
- ✅ 受保護目錄
- ✅ 快速連續刪除
- ✅ 符號連結處理
- ✅ 命令參數選項

詳細測試說明請參考 [TEST_README.md](TEST_README.md)

## 貢獻

歡迎提交 Issue 和 Pull Request！

### 開發指南

1. Fork 本專案
2. 建立你的特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交你的變更 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 開啟 Pull Request

## 授權

本專案採用 MIT 授權條款 - 詳見 [LICENSE](LICENSE) 檔案

## 致謝

感謝所有為更安全的命令列環境做出貢獻的開發者。

## 聯絡方式

如有任何問題或建議，歡迎透過 GitHub Issues 與我們聯繫。

---
## ⚠️ 重要免責聲明 / Important Disclaimer

**使用本工具前請務必詳讀以下聲明：**

🔴 **本工具僅提供基本的安全防護層，不能取代完整的備份策略**
- 此工具將檔案移至垃圾桶，但垃圾桶仍在同一個檔案系統上
- 硬碟故障、系統損壞、意外格式化等情況仍會導致資料永久遺失
- **請務必定期備份重要資料到外部儲存裝置或雲端服務**

🔴 **本工具按「現況」提供，不提供任何明示或暗示的保證**
- 作者不對使用本工具造成的任何資料遺失或損害負責
- 本工具可能存在未知的 bug 或相容性問題
- 使用者需自行承擔使用風險

🔴 **本工具不應在生產環境或關鍵系統上使用，除非您完全了解其運作方式**
- 建議先在測試環境中充分測試
- 了解垃圾桶機制的限制（如磁碟空間、跨檔案系統移動等）
- 確保您知道如何使用原生 `rm` 命令（`/bin/rm` 或 `\rm`）

🔴 **垃圾桶不會自動清理，需要定期手動管理**
- 垃圾桶會持續佔用磁碟空間
- 建議定期檢查和清理垃圾桶內容
- 長期累積可能導致磁碟空間不足

**English Version:**

🔴 **This tool provides only basic safety protection and CANNOT replace a complete backup strategy**
- Files are moved to trash, but the trash is still on the same filesystem
- Hard drive failure, system corruption, or accidental formatting can still cause permanent data loss
- **Always maintain regular backups of important data to external storage or cloud services**

🔴 **This tool is provided "AS IS" without any warranties, express or implied**
- The author is not responsible for any data loss or damage caused by using this tool
- This tool may contain unknown bugs or compatibility issues
- Users assume all risks associated with its use

🔴 **This tool should NOT be used in production or critical systems unless you fully understand how it works**
- Test thoroughly in a non-production environment first
- Understand the limitations of the trash mechanism (disk space, cross-filesystem moves, etc.)
- Ensure you know how to use the native `rm` command (`/bin/rm` or `\rm`)

🔴 **The trash is NOT automatically cleaned and requires manual management**
- Trash continuously occupies disk space
- Regularly check and clean trash contents
- Long-term accumulation may lead to insufficient disk space

---

## ⚠️ 再次提醒 / Final Reminder

**本工具不能也不應該取代完整的備份策略！**

- ✅ **請做好**：定期備份重要資料到外部儲存或雲端
- ✅ **請做好**：了解工具的限制和風險
- ✅ **請做好**：在測試環境先充分測試
- ✅ **請做好**：定期清理垃圾桶
- ❌ **請勿**：依賴垃圾桶作為唯一的資料保護措施
- ❌ **請勿**：在關鍵生產系統上未經測試就使用
- ❌ **請勿**：假設垃圾桶中的資料永遠安全

**This tool CANNOT and SHOULD NOT replace a complete backup strategy!**

- ✅ **DO**: Regularly backup important data to external storage or cloud
- ✅ **DO**: Understand the tool's limitations and risks
- ✅ **DO**: Test thoroughly in a test environment first
- ✅ **DO**: Regularly clean the trash
- ❌ **DON'T**: Rely on the trash as your only data protection measure
- ❌ **DON'T**: Use in critical production systems without testing
- ❌ **DON'T**: Assume data in trash is permanently safe

**使用本工具即表示您已閱讀、理解並同意上述所有免責聲明和限制。**

**By using this tool, you acknowledge that you have read, understood, and agreed to all the disclaimers and limitations stated above.**
