#!/bin/bash
#
# better-rm 安裝腳本 / Installation script for better-rm
# 
# 用法 (Usage):
#   curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash
#   或 (or):
#   wget -qO- https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash
#

set -e  # 遇到錯誤時立即退出 / Exit on error

# 顏色定義 (Color definitions)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 安裝目錄 (Installation directory)
INSTALL_DIR="$HOME/.better-rm"
REPO_URL="https://github.com/sieg-wang/better-rm.git"
TRUSTED_REPO_SSH_URL="git@github.com:sieg-wang/better-rm.git"
TRUSTED_REPO_SSH_SCHEME_URL="ssh://git@github.com/sieg-wang/better-rm.git"

# 輸出函式 (Output functions)
info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 檢查命令是否存在 (Check if command exists)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 只從 Sieg-owned repository 更新現有安裝。目錄名不是 provenance；
# configured branch remote 才是下一次 pull 真正會信任的來源。
# Update an existing installation only from the Sieg-owned repository. A
# directory name is not provenance; the configured branch remote is the source
# the next pull would actually trust.
is_trusted_repo_url() {
    case "$1" in
        "$REPO_URL"|"$TRUSTED_REPO_SSH_URL"|"$TRUSTED_REPO_SSH_SCHEME_URL")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_trusted_update_source() {
    local branch
    local remote
    local merge_ref
    local remote_url

    if ! branch=$(git symbolic-ref --quiet --short HEAD); then
        error "錯誤：現有安裝位於 detached HEAD，拒絕自動更新"
        error "Error: existing installation is on a detached HEAD; refusing automatic update"
        return 1
    fi
    if ! remote=$(git config --get "branch.${branch}.remote") ||
       ! merge_ref=$(git config --get "branch.${branch}.merge") ||
       [ -z "$remote" ] || [ "$remote" = "." ] || [ -z "$merge_ref" ]; then
        error "錯誤：目前 branch 沒有可驗證的 remote upstream，拒絕自動更新"
        error "Error: current branch has no verifiable remote upstream; refusing automatic update"
        return 1
    fi
    if ! remote_url=$(git remote get-url "$remote"); then
        error "錯誤：無法解析 upstream remote '$remote'，拒絕自動更新"
        error "Error: cannot resolve upstream remote '$remote'; refusing automatic update"
        return 1
    fi
    if ! is_trusted_repo_url "$remote_url"; then
        error "錯誤：拒絕從未信任的 upstream 更新：$remote_url"
        error "Error: refusing to update from untrusted upstream: $remote_url"
        error "預期來源 / Expected source: $REPO_URL"
        return 1
    fi
}

# 偵測使用者的 shell
# Detect user's shell
detect_shell() {
    local shell_name=$(basename "$SHELL")
    local shell_config=""
    
    case "$shell_name" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                shell_config="$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                shell_config="$HOME/.bash_profile"
            fi
            ;;
        zsh)
            if [ -f "$HOME/.zshrc" ]; then
                shell_config="$HOME/.zshrc"
            fi
            ;;
        *)
            # 嘗試常見的 shell 設定檔
            # Try common shell config files
            if [ -f "$HOME/.bashrc" ]; then
                shell_config="$HOME/.bashrc"
            elif [ -f "$HOME/.zshrc" ]; then
                shell_config="$HOME/.zshrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                shell_config="$HOME/.bash_profile"
            fi
            ;;
    esac
    
    echo "$shell_config"
}

# 主要安裝函式 (Main installation function)
install() {
    echo ""
    echo "================================================"
    echo "  better-rm 安裝程式 / Installation Script"
    echo "================================================"
    echo ""
    
    # 檢查 git 是否安裝 (Check if git is installed)
    if ! command_exists git; then
        error "錯誤：找不到 git 命令，請先安裝 git"
        error "Error: git command not found, please install git first"
        exit 1
    fi
    
    # 檢查安裝目錄是否已存在 (Check if installation directory exists)
    if [ -d "$INSTALL_DIR" ]; then
        info "發現現有安裝，正在更新... / Found existing installation, updating..."
        cd "$INSTALL_DIR"
        # 檢查是否為有效的 git 儲存庫 (Check if it's a valid git repository)
        if ! git status >/dev/null 2>&1; then
            error "錯誤：$INSTALL_DIR 存在但不是有效的 git 儲存庫"
            error "Error: $INSTALL_DIR exists but is not a valid git repository"
            error "請手動刪除該目錄後重試：rm -rf $INSTALL_DIR"
            error "Please manually remove the directory and try again: rm -rf $INSTALL_DIR"
            exit 1
        fi
        if ! require_trusted_update_source; then
            exit 1
        fi
        if git pull --ff-only --quiet; then
            success "更新成功 / Updated successfully"
        else
            error "更新失敗 / Update failed"
            exit 1
        fi
    else
        info "正在下載 better-rm... / Downloading better-rm..."
        if git clone --quiet "$REPO_URL" "$INSTALL_DIR"; then
            success "下載完成 / Downloaded successfully"
        else
            error "下載失敗 / Download failed"
            exit 1
        fi
    fi
    
    # 設定執行權限 (Set executable permission)
    info "設定執行權限... / Setting executable permission..."
    chmod +x "$INSTALL_DIR/better-rm"
    success "權限設定完成 / Permission set"
    
    # 偵測 shell 設定檔 (Detect shell config file)
    local shell_config=$(detect_shell)
    
    if [ -z "$shell_config" ]; then
        warning "無法自動偵測 shell 設定檔 / Could not auto-detect shell config file"
        echo ""
        echo "請手動將以下內容加入您的 shell 設定檔："
        echo "Please manually add the following to your shell config file:"
        echo ""
        echo "    alias rm='$INSTALL_DIR/better-rm'"
        echo ""
        exit 0
    fi
    
    # 檢查別名是否已存在 (Check if alias already exists)
    local alias_line="alias rm='$INSTALL_DIR/better-rm'"
    if grep -q "$alias_line" "$shell_config" 2>/dev/null; then
        info "別名已存在於 $shell_config / Alias already exists in $shell_config"
    else
        info "正在設定別名... / Setting up alias..."
        echo "" >> "$shell_config"
        echo "# better-rm: 更安全的 rm 命令 / A safer rm command" >> "$shell_config"
        echo "$alias_line" >> "$shell_config"
        success "別名已加入 $shell_config / Alias added to $shell_config"
    fi
    
    echo ""
    echo "================================================"
    echo -e "  ${GREEN}安裝完成！ / Installation Complete!${NC}"
    echo "================================================"
    echo ""
    echo -e "${GREEN}✓${NC} better-rm 已安裝完成並加入到 shell 設定檔"
    echo -e "${GREEN}✓${NC} better-rm installed and added to shell config"
    echo ""
    echo -e "${YELLOW}請執行以下命令立即啟用 better-rm (不需要重啟終端機)：${NC}"
    echo -e "${YELLOW}Run this command to activate better-rm immediately (no restart needed):${NC}"
    echo ""
    echo -e "    ${GREEN}alias rm='$INSTALL_DIR/better-rm'${NC}"
    echo ""
    echo "或者重新開啟終端機 / Or open a new terminal"
    echo ""
    echo "================================================"
    echo ""
    echo "驗證與使用 (Verification and Usage):"
    echo ""
    echo "1. 驗證安裝 / Verify installation:"
    echo -e "   ${BLUE}rm --version${NC}"
    echo "   應該顯示 'better-rm 1.5.0'"
    echo "   Should display 'better-rm 1.5.0'"
    echo ""
    echo "2. 查看使用說明 / View usage help:"
    echo -e "   ${BLUE}rm --help${NC}"
    echo ""
    echo "提示 (Tips):"
    echo "  • 檔案會被移至 ~/.Trash 而非永久刪除"
    echo "    Files will be moved to ~/.Trash instead of permanent deletion"
    echo "  • 如需使用原生 rm: /bin/rm 或 \\rm (反斜線可繞過別名)"
    echo "    To use native rm: /bin/rm or \\rm (backslash bypasses alias)"
    echo ""
}

# 執行安裝 (Execute installation)
install
