#!/bin/bash
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'
if ! command -v gh &> /dev/null; then
    echo -e "${RED}错误：未安装 gh CLI，请先安装。${NC}"
    exit 1
else

    if ! gh auth status &> /dev/null; then 
        echo -e "${RED}错误：gh未登录，请先执行 gh auth login。${NC}"
        exit 1
    fi
fi
# --- 内部函数：显示美化的仓库列表 ---
function list_repos() {
    echo -e "${YELLOW}--- 当前仓库清单 ---${NC}"
    # 获取数据并带行号显示
    gh repo list --limit 100 --json name,visibility --template '{{range .}}{{.name}}  {{.visibility}}{{"\n"}}{{end}}' | \
    column -t | \
    awk '{printf "  [\033[1;34m%2d\033[0m] \033[1;32m%-30s\033[0m [%s]\n", NR, $1, $2}'
}

# --- 核心函数：删除仓库 (支持方向键/手动输入) ---
function delete_repo() {
    if command -v fzf &> /dev/null; then
        echo -e "${BLUE}检测到 fzf，开启交互式选择模式... (按 ESC 退出选择)${NC}"
        # 让用户通过方向键搜索和选择
        REPO=$(gh repo list --limit 100 --json name -q '.[].name' | fzf --height 40% --border --prompt="选择要删除的仓库: ")
        
        if [ -z "$REPO" ]; then
            echo "未选择任何仓库。"
            return
        fi
    else
        # 如果没有 fzf，退回到手动列表和输入
        list_repos
        echo -e "${RED}请输入要删除的仓库全名:(按 ESC 取消删除)${NC}"
        read -p ">> " REPO
        if [ -z "$REPO" ]; then
            echo "取消删除。"
            return 
        fi
        
    fi
   
    # 最后的死亡确认
    if [ -n "$REPO" ]; then
        echo -e "${RED}！危险操作！确认删除仓库 '$REPO' 吗？(y/N)${NC}"
        read -p ">> " CONFIRM
        if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
            gh repo delete "$REPO" --yes && echo -e "${GREEN}仓库已成功彻底删除。${NC}"
        else
            echo "操作已取消。"
        fi
    fi
}

# --- 核心函数：改名并自动重连 ---
function rename_and_relink() {
    local current_repo new_url owner repo_to_rename original_url
    owner=$(gh api user -q '.login')
    if [ -d ".git" ] && git remote get-url origin &> /dev/null; then
        original_url=$(git remote get-url origin)
        CURRENT_REMOTE=$(git remote get-url origin | sed 's|.*[/:]||; s|\.git$||')
        echo -e "${BLUE}当前目录关联的远程仓库：${GREEN}$CURRENT_REMOTE${NC}"
        read -p "是否修改当前目录关联的仓库名称？(y/N): " USE_CURRENT
        if [[ "USE_CURRENT" == "y" ]] || [[ "USE_CURRENT" == "Y" ]]; then
            repo_to_rename="$owner/$CURRENT_REMOTE"
        fi
    fi 
    
    if [ -z "$repo_to_rename" ]; then
        if command -v fzf &> /dev/null; then 
            echo -e "${BLUE}检测到 fzf，开启交互式选择模式...(按 ESC 推出选择)${NC}"
            repo_to_rename=$(gh repo list --limit 100 --json nameWithOwner \
                -q '.[].nameWithOwner' | fzf --height 40% --border \
                --prompt="选择要改名的仓库: ") || true
        else
            list_repos
            read -p "请输入要改名的仓库名(不含owner)：" repo_to_rename
            [[ "$repo_to_rename" != */* ]] && repo_to_rename="$owner/$repo_to_rename"
        fi
    fi
    [ -z "$repo_to_rename" ] && echo "取消操作。" && return
    # 输入新名称
    read -p "请输入新的仓库名称：" NEW_NAME
    [ -z "$NEW_NAME" ] && echo "取消操作。" && return # ── 重新关联到原来的本地仓库 ──
    if [ -n "$original_url" ]; then
        new_url="https://github.com/$owner/$NEW_NAME.git"
        git remote set-url origin "$new_url"
        echo -e "${GREEN}本地关联已更新：$new_url${NC}"
    fi
    gh repo rename "$NEW_NAME" --repo "$repo_to_rename" --yes || return
    echo -e "${GREEN}仓库已成功改名为：$NEW_NAME ${NC}"
    if [ -n "$original_url" ]; then
        new_url="git@github.com:$owner/$NEW_NAME.git"
        git remote set-url origin "$new_url"
        echo -e "${GREEN}本地关联已更新：$new_url${NC}"
    fi
        
        
   
}

# --- 主循环菜单 ---
while true; do
    echo -e "\n${BLUE}==== GitHub 管理工具 ====${NC}"
    echo "1) 查看仓库列表 (List)"
    echo "2) 删除仓库 (Delete - 自动适配方向键)"
    echo "3) 修改当前仓库名并重连 (Rename)"
    echo "4) 退出 (Exit)"
    read -p "请选择操作 [1-4]: " OPT
    
    case $OPT in
        1) list_repos ;;
        2) delete_repo ;;
        3) rename_and_relink ;;
        4) break ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
done
