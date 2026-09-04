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
curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash
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
git clone https://github.com/sieg-wang/better-rm.git ~/.better-rm
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
git clone https://github.com/sieg-wang/better-rm.git
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

`v2` 標記代表兩個路徑欄位是轉義過的：`\\` 反斜線、`\p` 直線 `|`、`\n` 換行、`\r` 歸位、`\s` 分號 `;`、`\a` 和號 `&`、`\g` 反引號、`\d` 錢號 `$`。前四個維持一筆紀錄一行、欄位不被分隔符切錯；後四個讓紀錄無法被當成 shell 命令執行——整筆紀錄長得就像一條 pipeline，未轉義的 `;`、`&`、`` ` ``、`$( )` 會在有人 source 或 eval 這些位元組時真的執行。因此含有 `|`、換行或 shell 元字元的合法檔名都能被正確記錄與還原。沒有 `v2` 標記的紀錄是升級前寫下的舊版 5 欄格式（`TIMESTAMP | ORIGINAL_PATH | TRASH_PATH | HASH | FILE_TYPE`），`--restore` 仍可讀取。

日誌檔本身必須是「本人所有、單一連結的一般檔案」。路徑上若已經是 symlink、hard link、FIFO 或別人的檔案，better-rm 會印出警告並停止記錄（刪除本身照常完成），不會沿著它把紀錄寫進別的檔案。日誌權限不列入判斷：從備份還原或落在 FAT／雲端掛載點的 0644 日誌照樣可用。

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

### 自行宣告受保護的目錄

`BETTER_RM_PROTECTED_DIRS` 可以把你自己的目錄加進保護清單，兩道守衛都認：`rm` 替身
（本工具）與 coding agent 那道 PreToolUse hook。

```bash
# 暫時設定（單次使用）
BETTER_RM_PROTECTED_DIRS="$HOME/work/secrets" rm -rf ~/work/secrets

# 永久設定（在 ~/.bashrc 或 ~/.zshrc 中加入），多個目錄以 : 分隔
export BETTER_RM_PROTECTED_DIRS="$HOME/work/secrets:$HOME/vault"
```

- 以 `:` 分隔，空項會被略過（所以結尾多一個冒號不會把你的工作目錄變成刪不掉的）。
- 相對路徑以目前的工作目錄為基準解析。
- 與內建清單一樣是完全比對：保護的是宣告的那個目錄本身，`secrets/notes.txt` 仍可刪除。

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
- `/private/etc`、`/private/var` - macOS 的 `/etc` 與 `/var` 是指向這兩個目錄的 symlink
  （`readlink -f` 實測），資料真正放在這裡。比對是精確比對，所以保護 `/etc` 而不保護
  `/private/etc`，等於保護了一個名字、沒保護那份資料。`/private/tmp` 刻意不在清單上——
  那是暫存工作的地方。

### 使用者目錄

- `~` 或 `$HOME` - 你的家目錄（整個目錄）
- `~/.ssh` - SSH 私鑰、`known_hosts` 與 `config`
- `~/.claude` - Claude Code 的設定、hooks，以及 `projects/` 底下的對話記錄

這兩項與清單上其他項目**完全相同**的語意：保護的是那個目錄本身，不是它底下的東西。
`rm -rf ~/.ssh` 被拒絕，`rm -f ~/.ssh/known_hosts.old`、`rm -rf ~/.claude/projects/<session>`
照舊放行——後者是會長到數 GB、本來就會定期清理的對話記錄。唯一不那麼直觀的地方是萬用
字元：父目錄受保護的樣式選中的是**整個目錄的內容**，所以 `rm -rf ~/.ssh/*` 與
`rm -rf ~/.claude/*` 會被拒絕，理由與 `rm -rf /etc/*` 相同；`rm -rf ~/.claude/projects/*`
的父目錄沒受保護，照舊放行。名字只是「以它開頭」的鄰居不受影響（`~/.claude-backup`、
`~/.sshfoo`）——比對的是完整路徑元件，不是前綴。

寫法不影響判定：`~/.ssh`、`"$HOME/.ssh"`、`$HOME/.ssh`、`"${HOME}/.ssh"`、`/Users/<you>/.ssh`
與結尾多一條斜線的 `~/.ssh/` 全部得到同一個答案，包裝與載體（`sudo rm -rf ~/.ssh`、
`find "$HOME/.ssh" -delete`、`echo ~/.ssh | xargs rm -rf`、`bash -c 'rm -rf ~/.ssh'`）也是。
在此之前，只有「解不開的變數」這個意外讓 `rm -rf "$HOME/.ssh"` 看起來被擋住（而且拒絕訊息
報的是一個沒人寫過的 `/`），字面的 `rm -rf ~/.ssh` 一直都是放行的。

**`~/Library` 刻意不在清單上。** 清 `~/Library/Caches/<tool>` 是例行工作，而這份清單保護的
是目錄本身而非內容——加上去對常見的清快取命令沒有任何幫助，卻會把 `rm -rf ~/Library/*`
這類清理變成拒絕。在一道沒有豁免管道的守衛上，誤擋是實實在在的成本，而這一項換不到對等
的收益。`~/Library`、`~/Library/Caches/pip` 照舊可刪，測試套件裡有對應的列釘住這個決定：
哪天有人把它加進清單，那幾列會轉紅。

同樣要說清楚**沒有**涵蓋的部分：判定是在命令執行前對命令文字做的，所以
`cd ~ && rm -rf .ssh` 這種先換目錄、再用相對路徑的寫法不會被擋——閘門看到的是相對於本次
工具呼叫 cwd 的 `.ssh`。這一點對 `/etc` 也一樣（`cd / && rm -rf etc`），不是這兩項特有的，
也不是本次新增的。

**`cd` 不是唯一的換目錄寫法。** env(1) 自己就有：BSD env 的 `env -C <dir> …`（本機
`env` 的 usage 行就寫著 `[-C workdir]`）與 GNU env 的 `env --chdir=<dir> …` 都會在執行
命令前換掉工作目錄，於是 `env -C / rm -rf etc`、`env --chdir=/ rm -rf etc` 與上面那條
`cd / && rm -rf etc` 是同一件事、同樣不會被擋。閘門會把這兩個選項連同它的值一起跳過，
但不會把那次 chdir 接進判定裡，所以相對路徑仍然是對著本次工具呼叫的 cwd 解讀的。
（2026-09-05 用 mkdir marker 實測：BSD env 吃 `-C`、GNU env 吃 `--chdir=`，兩者都真的
在目標目錄裡建出了檔案；BSD env 不認 `--chdir=` 這個寫法。）絕對路徑的操作元不受影響
——`env -C /tmp rm -rf /etc` 照樣被拒——以名字認定的項目也一樣，例如
`env -C / rm -rf .git`。要它照一般規則被判定，就把目標寫成字面的絕對路徑。

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
- 侷限：這是拼寫上的對應，不是身分證明。`/System/Volumes/Data/usr` **是存在的**——它裝著
  `/usr/local`、`/usr/libexec/cups`、`/usr/share/snmp` 這幾條 firmlink 在資料卷宗上的本體
  （見 `/usr/share/firmlinks`），inode 也與 `/usr` 不同，卻仍會被對應成 `/usr` 一併拒絕：
  擋下的是一個真實存在、但不是 `/usr` 的目錄。方向是安全的那一邊，代價也小——真正與
  `/usr/local` 同一顆 inode 的 `/System/Volumes/Data/usr/local` 對應成 `/usr/local`，照舊可刪。
  反過來，bind mount、hardlink 目錄之類「同一顆 inode、兩種拼寫」不在這條規則涵蓋範圍內。

清單其餘各項以完全相同的路徑比對，保護的是那個目錄本身而非其內容：`/Applications/Xcode.app`、
`/Library/Caches/foo` 這類目錄內的項目仍可正常移除。`/private` 同樣只涵蓋 `/private` 本身，
而 `/private/etc`、`/private/var` 各自都在清單上（macOS 的 `/etc`、`/var` 就是指向它們的
符號連結，只保護符號連結那個名字等於沒保護那份資料）。這段先前寫的是「以實體路徑書寫
（`rm -rf /private/etc`）不在保護範圍內」——那是 b0c5871 之前的狀態，兩個名字加進兩份清單
之後就不再成立，這裡一併更正。

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
| `$(which echo) "$LOGFILE"` | 不在解析清單上的變數仍是動態的 |
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
| `$(which cat) $HOME/.zshrc` | `$HOME` 會被解析，而它不是家目錄本身 |
| `$(which cat) ~/.zshrc` | `~/…` 展開後不是受保護路徑（裸 `~` 才是） |
| `` `pwd` status `` | 反引號內沒有空白 → 不會多切出動態片段 |
| `cd $(git rev-parse --show-toplevel)` | `$( )` 不在執行檔位置 |

**`$HOME`、`$PWD`、`$TMPDIR` 會先解析再判定。** 這三個變數的值 hook 知道，因此不再
折成最壞情況，而是代入實際值、再走**一般的**受保護路徑判定 —— 所以
`rm -rf "$HOME/projects/foo/build"` 允許、`rm -rf "$HOME"` 照舊拒絕，
變數拼法與它展開成的字面路徑得到同一個答案。`$PWD` 取的是這次工具呼叫的 cwd，
`$TMPDIR` 取自 hook 拿到的環境。**清單就這三個，其餘一律維持未知並拒絕**
（`$LOGFILE`、`$BUILD_DIR`、`${WORK}`、`$1`、`$@`、`$$`、`$( … )`、反引號皆然），
`${VAR:-預設值}` 這類運算也沒有建模，同樣視為未知。名稱比對是完整比對，
`$HOMEBREW_PREFIX` 不是 `$HOME`。

只要命令自己可能改掉那個值就停止解析，退回原本的拒絕：出現 `HOME=`、`PWD=`、
`TMPDIR=` 形式的賦值（含 `HOME=/ rm -rf "$HOME/etc"` 這種前置賦值），或出現
`unset`／`export`／`declare`／`typeset`，或出現 `cd`／`pushd`／`popd`（那會移動 `$PWD`）。

**值裡有空白就不解析。** 沒加引號時，這種值不是「一條路徑」：shell 會把它切開，rm 拿到的
是好幾個操作元。實測 `TMPDIR='/tmp/x /etc'` 時 `rm -rf $TMPDIR` 真的會刪掉 `/etc`，而整段
代入後得到的單一字只是一條普通路徑。這道閘門在那個位置看不到引號，只能假設會被切開，因此
改為不解析、維持未知並拒絕。代價：家目錄或 TMPDIR 含空白的機器，所有 `$HOME` 命令都會退回
「未知而拒絕」。

**殘留風險（明講）**：hook 是在**它自己的環境**裡解析這三個變數。若某個變數在 hook
看到的值與命令實際執行時的值不同（例如由父行程之外的機制改寫），判定會依 hook 看到的
值做出。發生機率低，但確實存在，因此寫在這裡而不是留給你自己發現。

**只有「目標」會解析，命令位置不會。** 展開後才知道的執行檔照舊一律假設成 rm 並掃描它的
操作元，所以 `eval ${HOME} /System` 會拒絕，而字面的 `eval /Users/you /System` 不會。這是
安全的方向、也比解析更早存在，但它代表變數拼法與字面拼法「只有在目標位置」可以互換。

**解不開時的訊息會直說「不知道」**，不會再宣稱你刪的是受保護目錄、也不會顯示一條你沒寫過的
`/`；訊息會指名解不開的那個操作元，並給出繞法：把目標改寫成**字面的絕對路徑**，它就會照
一般規則被判定。這句繞法原本寫的是 `cd <目錄> && rm -rf <相對路徑>`，那是錯的：判定是拿
命令文字對著呼叫端的 cwd 做的，`cd` 不會被算進去，所以那個形狀不只繞過這一項，是繞過
**每一個**受保護項目（見上面 `cd ~ && rm -rf .ssh` 那一段）。

**判定有 2,000ms 的時間預算，超過就拒絕沒讀到的部分。** 單一目標的成本有上限，但目標的
「數量」是命令自己決定的，而目標是 symlink 時要對每一個宣告項目各做一次 `lstat`。實測
（刪的都是真的 `/etc`）：`rm -rf <60,000 個相對 symlink 操作元> /etc` 在上一版要 6,215ms、
同一形狀寫成 30MB 時根本沒有回答——而 live hook 的逾時是 5,000ms，**逾時的 PreToolUse hook
不做任何裁決，也不會擋下命令**。所以現在改成：時間用完就以「我停止讀了」拒絕，訊息會寫出
判了幾個、總共幾個，並建議拆成多條命令。用「時間」而不是「數量」，是因為每個目標的成本差
兩個數量級：先試過 5,000 的數量上限，它會誤擋 `find . -exec rm …×6000`（6,001 個目標、
118ms、什麼都不刪）。**未涵蓋的部分明講**：產生目標的斷詞在第一次檢查之前就跑完，2,000ms 的預算管不到它。
2026-09-04 補上一道**「失敗讀取」預算**（`MAX_FAILED_SUBSTITUTION_READS = 64`）：雙引號裡的
`$(`／`${`／`` ` `` 讀不到收尾時會掃到輸入結尾、而呼叫端只前進一個字元，於是「沒收尾的開頭
數」是平方級的成本。實測（走真正的 stdin 進入點，命令是 `echo "` + 開頭字 ×n + `" ; rm -rf
/etc`）：`${` 在 117KB 要 6,071ms，超過 live 的 5,000ms 逾時，加上預算之後是 52ms。
**只有「失敗」的讀取花預算**，所以替換讀得完的真實命令碰不到它。**仍未涵蓋**：`$(` 那一半的
成本主要在命令替換掃描裡，那是既有的、與這次改動無關的平方級成本——117KB 從 37,015ms 降到
18,355ms，仍然遠超過逾時。要完全封住只剩「輸入長度上限 + fail-closed 拒絕」一條路，而那是
姿態改變（實測：上限要壓到 16KB 才有餘裕），屬於使用者的裁決，見 KNOWN-RESIDUALS.md 的 R5-a。

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

### 從 pipe 或 process substitution 進來的腳本會被拒絕（規則：unscannable piped script）

當 shell（`bash`／`sh`／`dash`／`zsh`／`ksh`／`fish`／`csh`／`tcsh`／`source`／`.`，含
`sudo`／`env`／`timeout`／`nice` 等外殼）要執行的**腳本本身**是從 pipe 或 process
substitution 進來的，這道閘門必須先讀得到那段腳本，否則**拒絕執行**。理由是實測出來的：
`cat <<EOF | bash` 與 `bash <<< "…"`（腳本寫在命令列上）一直是被判定的，而逐位元組等價的
`echo "rm -rf /etc" | bash`、`curl … | bash`、`cat f | bash`、`bash <(…)`、
`… | tee f | bash` 一路放行——差別只在腳本從哪裡進來，不在它做什麼。

讀得到的兩種產生器照舊放行：

| 產生器 | 結果 |
|---|---|
| 字面產生器：`echo`／`printf` 的字（沒有 `$`、反引號）、`cat <<EOF` | 讀出來當巢狀命令判：`echo hi \| bash` 允許，`echo "rm -rf /etc" \| bash` 以受保護目錄 `/etc` 拒絕。**掃的文字有四份**：原樣接起來的 argv、把開頭的選項字拿掉之後的 argv（`printf` 再多丟掉格式字串）、每一個含空白的操作元，以及**把上面每一份的反斜線逸出序列解碼過的版本**（`\xHH`、`\0nnn`／`\nnn`、`\uHHHH`／`\UHHHHHHHH`、`\t \n \v \f \r \a \b \e \\`）。解碼刻意**不以 `-e` 為條件**：dash 與 ksh 的 echo 預設就解碼、`bash -O xpg_echo` 讓 bash 的也解碼（實測 payload 真的執行），而 printf 永遠解碼格式字串、`%b` 連參數一起解——讀 pipe 的是哪個 shell，這道閘門看不到。解碼版是**加進**掃描集合而不是取代原文，所以只會把放行變成拒絕。少了第四份，`echo -e 'rm\x20-rf\x20/etc' | bash` 在這條命令列上只是**一個** shell 字，`rm` 在四份文字裡都不在命令位置，2026-09-04 之前是**放行**的（實測 touch payload 在 bash 5.3.15、/bin/bash 3.2.57、/bin/sh、zsh、/bin/csh 下都真的執行）。少了中間那一份，`echo -e rm -rf /etc \| bash` 這種「刪除被寫成分開的字」的寫法在任何一份文字裡 `rm` 都不在命令位置上，2026-09-04 之前是**放行**的（實測 touch payload 在 /bin/bash 3.2.57、bash 5.x、sh、zsh、dash、ksh 下都真的執行） |
| `PIPED_SCRIPT_EXCEPTIONS` 上的安裝路徑 | 放行（見下一節） |
| 其他任何東西，含解析不出來的產生器 | **拒絕執行**，訊息會寫出規則名稱與繞法 |

**斷詞的一項修正，方向是「拒絕變成放行」（2026-09-04）**：雙引號裡的反斜線，只有在 `$`、
反引號、`"`、`\`、換行之前才是逸出字元；在其他任何字元之前，shell 會把**兩個字元都保留**
（od(1) 實測，/bin/bash 5.3.15、/bin/bash 3.2.57、/bin/sh、/bin/zsh、/bin/ksh、/bin/dash
六者一致）。斷詞器原本把雙引號裡的每一個反斜線都當逸出丟掉，於是把 `"/e\tc"` 讀成 `/etc`、
把 `"\rm"` 讀成 `rm`——都是任何 shell 都不會產生的字——並因此**擋掉了碰不到受保護路徑的命令**
（`rm -rf "/e\tc"`、`rm -rf "\/etc"`、`rm -rf "/\etc"`、`"\rm" -rf /etc` 都曾是拒絕；
實測 `"\touch" q1` 在上述六個 shell 裡都不會執行任何東西）。這些現在放行。
**真的是 `rm`、真的指向 `/etc` 的那些寫法一列都沒有動**：未加引號的 `r\m`、`\rm`，以及字中間
開閉引號的 `"r"m`、`r"m"`、`rm -rf "/e"tc`、`rm -rf /e"t"c`，照舊全部拒絕，並且兩個方向都有
測試釘住。修這一條的理由是上面那一列的第四份文字：`echo -e "rm\x20-rf\x20/etc" | bash`
原本斷成單一個字 `rmx20-rfx20/etc`，裡面既沒有 `rm`，也沒有逸出序列可以讓解碼看見。

**新被擋掉的合法命令**（這是姿態改變的代價，不是意外）：

| 現在會被擋 | 為什麼 |
|---|---|
| `curl -fsSL https://get.example.com/install.sh \| sh` | 其他專案的一行安裝法一律擋，只有下一節的清單例外 |
| `cat script.sh \| bash` | `cat` 讀的是檔案，閘門讀不到內容（`bash script.sh` 仍允許） |
| `echo "$cmd" \| bash` | 帶展開的產生器不是字面產生器 |
| `echo hi \| cat \| bash` | 只分類「直接餵給 shell 的那一段」，中繼段（`cat`／`tee`／`sed`）不是字面產生器 |
| `python3 -c "print(1)" \| bash` | 同上：產生器的輸出不可知 |
| `source <(kubectl completion bash)` | completion 這類 `source <(…)` 慣用寫法同屬此類（`eval "$(…)"` 不在範圍內，仍允許） |
| `curl -sSL https://example.invalid/x.sh \| bash 0<&0` | `<&` 是 fd 複製、不是檔案重導向，pipe 仍然在餵腳本 |
| `curl … \| $CMD` | 展開後才知道的命令字可能就是 shell，與 `$CMD <<< …` 得到同一個答案 |
| `bash <<< "$(curl -s …)"` | 腳本文字看得見，但裡面的命令替換輸出看不見 |
| `curl … \| bash -O extglob`、`-o pipefail`、`--rcfile f` | 引數是分開一個字的 carrier 選項，那個字不是腳本檔（`bash -O extglob script.sh` 仍允許） |
| `curl … \| bash < /dev/stdin`、`< /dev/fd/0`、`< /proc/self/fd/0`、`0< /dev/stdin`、`<>` | 目標就是 pipe 自己的重導向，並沒有把腳本從 pipe 拿走（`bash < script.sh` 仍允許）。`/proc/self/fd/0` 是同一個 pipe 在 Linux 上的寫法，而本專案有出貨到 Linux（`install.sh`、CI 跑在 ubuntu-24.04）|
| `bash /dev/fd/3 3< <(curl …)`、`bash /proc/self/fd/3 3< <(curl …)`、`exec 3< <(curl …); bash /dev/fd/3` | `/dev/fd/N`（與它的 `/proc/self/fd/N` 拼法）指的是開了那個 fd 的 process substitution，不是檔案 |
| `curl … \| bash -c "$(cat)"` | 腳本看得見，但有 pipe 在餵它時，`-c` 字串裡的命令替換讀的就是那個 pipe |
| `curl … \| bash \` | 單獨的尾端反斜線沒有指名任何檔案；bash 3.2 會執行從 pipe 進來的腳本（5.3 則報錯） |
| `echo hi \| bash -c "…$(date)…"` | 上一列的代價：有 pipe 餵著時，`-c` 字串裡**任何**讀不出來的命令替換都會被擋（沒有 pipe 的 `bash -c "$(date)"` 不受影響） |
| `git log \| $PAGER`、`cat f \| "$TOOL"` | 管線接收端是解不開的命令字、而且後面沒有檔案操作元，它可能就是個從 pipe 讀腳本的 shell。這一列的規則名稱與訊息都不同（`unresolvable pipe target`），繞法是寫成絕對路徑或給它一個檔案操作元 |

繞法（訊息裡也會寫）：`curl -o install.sh <url> && bash install.sh`（先存檔、讀過再跑），
或把命令寫成字面的 `bash -c '<命令>'`。

**不是誤擋、刻意仍然允許**（下面三類先前被這條規則擋掉，那是誤擋，已修）：

| 現在允許 | 為什麼 |
|---|---|
| `… \| xargs -n1 bash -n`、`cat f \| env bash -n`、`\| timeout 5 bash -n`、`\| nice bash -n`、`\| sh -n`、`\| zsh -n` | `-n`（noexec）只解析不執行，這正是各套測試對每個 shell 檔跑的語法檢查。**沒有 `-n` 就照擋**：`… \| xargs -n1 bash`、`cat f \| env bash`、`cat f \| timeout 5 bash` 仍是拒絕 |
| `ps aux \| "$HOME/bin/filter.sh"`、`ls \| "$PWD/tool.sh"`、`ls \| "$TMPDIR/tool"` | 管線接收端展開後才知道，但 `$HOME`／`$PWD`／`$TMPDIR` 這道閘門本來就會解（與 rm 操作元同一份清單），解出來的 basename 不是 shell 就不是 carrier。解不開的（`$TOOL`、`$PAGER`、`${PAGER:-less}`）照舊拒絕，而解出來確實是 shell 的（`"$HOME/bin/bash"`）也照舊拒絕 |
| `cat a.txt \| $JQ -S .`、`git log \| $PAGER x` | **arity 規則**：解不開的命令字後面帶了一個非選項操作元，它讀的是那個操作元而不是 pipe。只帶選項（`$PAGER -S`）或什麼都不帶（`$JQ`）則仍然拒絕 |

**仍然允許、刻意不在這條規則範圍內**：`bash < script.sh`、`bash script.sh`、
`bash -c "$(curl …)"`（**沒有 pipe 餵著時**——有 pipe 的 `curl … | bash -c "$(cat)"` 是拒絕的）、
`eval "$(curl …)"`、`… | xargs -I{} bash -c "{}"`（**`-c` 後面帶著字面命令字串時**；
`… | xargs -0 bash -c` 這種沒有命令字串、由 xargs 把 pipe 內容補上去的寫法不在此列）、
`curl … > >(bash)`（輸出方向的 process substitution）、`busybox sh` 與其他非 shell 消費端。
`cat f | bash` 被擋而只差一個字元的 `bash < f` 沒被擋，所以知道規則的人繞得過去：
這條規則買到的是「閘門不再對一種常見寫法視而不見」，不是「對手拿不到執行」。
完整清單見 KNOWN-RESIDUALS.md 的 R4-b。

### 允許的 piped installer 清單 / Allowed piped installers

上一條規則唯一的豁免，是 `hooks/protect-important-paths.js` 裡的
`CANONICAL_INSTALL_LINES`：**一份「整條命令列」的清單**。命令列必須就是清單上的其中一行，
才會被豁免。另有一份 `PIPED_SCRIPT_EXCEPTIONS` 是網址前綴的第二道關卡（縱深防禦），今天
它只有一項：

```
https://raw.githubusercontent.com/sieg-wang/better-rm/
```

它涵蓋本 README 記載的四條安裝路徑，而且只涵蓋這四條：

```bash
curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash
wget -qO- https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash
curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh | bash -s -- -a claude
curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh | bash -s -- -a claude --global
```

**這份清單不是身分驗證。** 它比對的是命令列上的**網址文字**：任何能寫出那條命令的人都能
寫出這個前綴，而這道閘門無法驗證伺服器回什麼。它的職責只是不要讓上一條規則擋掉本專案自己
記載的安裝方式，不是建立信任。把它讀成授權機制、然後放寬它，就會把它變成一張通行證。

**怎麼擴充**（這是使用者的決定，不是解析器的）：新增一條安裝路徑要改**兩個地方**——把
**整條命令列**加進 `hooks/protect-important-paths.js` 的 `CANONICAL_INSTALL_LINES`，並確認
它的網址前綴在 `PIPED_SCRIPT_EXCEPTIONS` 上（形狀是 `scheme + host + owner/repo` 而且
**以 `/` 結尾**）。同一條路徑也必須寫進上面那個區塊，否則測試會紅（見本節最後一段）。

- 不要加裸 host（`https://raw.githubusercontent.com/` 會豁免那台主機上的每一個 repo）。
- 不要省略 scheme（沒有 scheme 的前綴會命中更長的主機名，例如
  `raw.githubusercontent.com.evil.tld`）。
- 不要用 `http://`，不要用萬用字元——比對就是 `startsWith`，維持這麼簡單。
- 結尾的 `/` 是有作用的：少了它，`better-rm-evil` 也會命中。

**豁免只有一個條件：整條命令列必須就是上面那四行的其中一行。** 比對之前只做兩件事：去掉
前後的 ASCII 空白（尾端的換行算在內），以及把連續的空白／tab 併成一個空格；除此之外必須
逐位元組相同。行上不可以有別的東西：

- **前面不行**——`cd /tmp && …`、`if true; then …; fi`、`set -e; …`、`FOO=1 …`、`sudo …`、
  `env …`，以及任何寫在它前面的另一條命令（`echo sourced; …`、`ls ./install.sh; …`）。
- **後面不行**——`…; echo done`、`… && …`、`… | tee x`、`… # 註解`。
- **中間不可以有換行**：`curl … |`（換行）`bash` 不是這一行。
- **引號與跳脫寫法不算同一行**：`\curl …`、`"curl" …`、`'curl' …` 都會被拒絕，即使 bash
  解析到的是同一個執行檔。
- **同一條路徑的其他寫法也不算**：選項換順序（`-sSfL` 之於 `-sSL`）、多一個選項
  （`… | bash -O extglob`）、多一個重導向（`… 2>/dev/null | bash`、`… | bash < /dev/stdin`）、
  主機名大小寫不同，全都不是這一行。
- **豁免只看使用者打的那一行**：`bash -c '<豁免路徑>'`、`echo '<豁免路徑>' | bash`、
  `BASH_ENV=… bash -c '<豁免路徑>'` 這種「要靠這道閘門自己重建出來才變成記載路徑」的寫法，
  一律拒絕。

上面每一種都是**已接受的代價**，不是缺陷：它們在 2026-09-04 以前是放行的，現在會落回
「讀不到的 piped script」拒絕。**繞法是把那條路徑單獨寫成一行。**

**為什麼是整行，而不是一組收窄條件。** 2026-09-03 起的三輪做的都是同一件事：列舉「一行上
有多少種方法能把別的東西塞到 `curl` 後面」——重新定義同名函式、`alias`、`hash -p`、`eval`、
`source`、點命令、`trap`、`exec`、把定義塞進一個字裡、把關鍵字拆開寫。每一輪都補上了前一輪
被打穿的寫法，然後被下一種沒被列舉到的寫法打穿。最後一次是**字裡面的引號消去**：
`e''val 'c''url() { … }'; <豁免網址> | bash` 的原始位元組裡既沒有 `eval` 也沒有 `curl(`，
而斷詞之後那個定義是**一個字**——兩種掃法都看不到它，shell 的引號消去卻會把兩者都還原
（2026-09-05 走真正的 stdin 入口實測：函式真的被定義、替身真的被執行，bash 5.3.15 與
/bin/bash 3.2.57 皆然）。整行字面比對關掉的是**整個類別**，理由不是「這次列舉得比較完整」：
攻擊者多打的任何一個字元，都是讓這一行不再是這一行的字元。

那些列舉出來的收窄條件**沒有被刪掉**（產生器必須是赤裸的 `curl`／`wget`、只有一個非選項
操作元、網址不得含 `..`／`%2e`／`%2f`／`%5c`、選項採白名單、同一行不得重新定義產生器的名字）。
它們留在程式碼與測試裡當縱深防禦，只是在整行規則之下**已經到不了**：逐位元組等於記載路徑的
一行，本來就不可能同時帶著前綴、第二個操作元、白名單外的選項或一個函式定義。

上面每一條（四條放行與它們的空白寫法、以及 owner 換掉、port 寫法、host 後綴、repo 前綴、
`..`、`%2e`、第二個網址、`--connect-to`／`--resolve`／`--proxy`／`--unix-socket`／`-K`／
`-o`，加上本節列出的每一種前綴、後綴、重導向、選項順序、引號寫法與重建寫法）都在
`test-hooks.js` 的 `installRouteAllowances`、`exceptionListControls`、`wholeLineRuleCosts`、
`inWordQuoteRemovalBlocked`、`offLineProducerBlocked` 裡，走真正的 stdin 契約跑過；放寬規則
而不改測試，測試會紅。`CANONICAL_INSTALL_LINES` 與上面那個程式碼區塊還會被**逐行、照順序、
逐位元組**比對：只改其中一邊，測試一樣會紅。

### `find` 什麼時候被當成刪除工具

絕大多數的 `find` 只是在讀，全部當成刪除工具會擋掉列檔案，所以 hook 只在 `find`
**真的會刪**的時候才判它走過的路徑：出現 `-delete`，或 `-exec`／`-execdir`／`-ok`／
`-okdir` 要跑的命令是 `rm`／`rmdir`。要跑的命令會先拆掉外殼再比對，所以
`-exec sudo rm`、`-exec nice rm`、`-exec env SAFE=1 command rm` 與 `-exec rm` 判定相同。
`-exec` 命令自己的操作對象也會被判（`find . -exec rm -rf /etc \;` 每找到一個檔案就對
`/etc` 跑一次 `rm`），而外殼自己的選項值不會（`sudo -u root` 裡的 `root` 不是刪除目標）。

**`\;` 是子句終止符，不是命令結束。** 收掉 `-exec` 子句的 `;` 必須躲開 shell，所以寫成
`\;` 或 `';'`；三種拼寫斷詞後長得一模一樣，但只有**裸的** `;` 會結束命令。hook 靠斷詞器
留下的旗標分辨，因此 `find /etc -exec cat {} \; -delete` 會被拒絕（實測真的 BSD `find`
會把整棵樹刪光），而 `find . -exec ls {} ; -delete` 裡的裸 `;` 照舊結束命令，後面那一段
各自判斷。只有 `;` 與 `+` 會終止子句（POSIX），所以跳脫或加引號的 `|`、`&`、`(`
不會——`find /etc -exec cat {} '|' -delete` 實測回 `no terminating ";" or "+"`、exit 1、
什麼都沒刪，因此不擋。

**已知仍然放行的形狀**（列出來，而不是留給你踩到；每一種在先前的版本也一樣放行）：
`-exec` 後面接 shell carrier（`find . -exec sh -c 'rm -rf /etc' \;`，以及 `bash`、`zsh`、
`sudo sh` 的拼寫）、經 `xargs` 到達的 `rm`、命令字要展開後才知道的
（`-exec $CMD -rf /etc`、`"$CMD"`、反引號），以及巢狀的
`find … -exec find … -exec rm`。這些在命令位置上寫同樣的字會被擋，`-exec` 後面不會：
兩邊共用的是「外殼清單」，不是整套判定。

### 自動安裝 Coding Agent hooks / Automatic Coding Agent hook installation

`install-hooks.sh` 目前已支援下列 Agent：`claude`、`codex`、`cursor`、`copilot`、`antigravity`、`qoder`、`pi`、`opencode`、`grok`。

推薦用一行指令（從 Sieg-owned repository 抓取安裝程式）：

```bash
curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh | bash -s -- -a claude
```

如果有需要全域安裝 Claude 設定：

```bash
curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh | bash -s -- -a claude --global
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
- **覆蓋是以 rename 就位**：還原時，垃圾桶項目會先搬進一個本行程獨佔建立的暫存目錄，再用同一檔案系統內的一次 rename 就位；讓位已經在這之前完成，所以 rename 通常落在一個空的路徑上，過程中不存在「先把目的地刪掉」的步驟。就位那一次 rename 一律是 `-n`，絕不覆蓋：您同意覆蓋的是「還原開始時佔著目的地的那一個物件」，而它已經在讓位時進了垃圾桶，所以走到就位時目的地照理是空的。此刻若還有東西佔著，那必定是讓位之後才被別的行程放上來的另一個物件，沒有人同意過覆蓋它——還原會中止（結束碼 `1`）、把垃圾桶項目放回，兩邊的東西都還在，而不是把後來者原子地換掉。跨裝置的複製發生在暫存目錄裡，複製失敗時目的地完全沒被碰過。若目的地起初不存在、卻在還原途中才出現，未經覆蓋同意的還原會中止並把垃圾桶項目放回，而且那個目的地連一次 mv 的落點都不會是。
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
