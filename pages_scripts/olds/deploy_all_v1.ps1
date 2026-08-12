<#
.SYNOPSIS
  GitHub Pages 通用部署脚本 (PowerShell版) - 新手友好版
  复制到任意文件夹，右键"使用 PowerShell 运行"
  支持新电脑从零开始引导：Git 安装 → GitHub CLI 安装 → 登录 → 选择账户 → 部署

  两种部署模式：
    1. 独立仓库模式：把当前文件夹部署为同名 GitHub 仓库并开启 Pages
       访问地址: https://<user>.github.io/<repo>/
    2. 主仓库子文件夹模式：上传到 <user>.github.io 仓库的同名子文件夹下
       访问地址: https://<user>.github.io/<subfolder>/  (和模式1地址相同！)
.PARAMETER PushOnly
  内部使用，仅执行 push 更新（已有仓库时调用）
#>
param([switch]$PushOnly)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "GitHub Pages 一键部署（新手指南版）"

# ═══════════════════════════════════════════════
#  ─── 全局变量 ───
# ═══════════════════════════════════════════════
$BRANCH = "main"
$FOLDER = $PWD.Path
$CONFIG_FILE = ".deploy-config.json"
$GH_USER = $null   # 登录成功后赋值

# ═══════════════════════════════════════════════
#  ─── Banner ───
# ═══════════════════════════════════════════════
Write-Host ""
Write-Host "╔" -NoNewline
Write-Host "═════════════════════════════════════════════════" -NoNewline
Write-Host "╗" -ForegroundColor White
Write-Host "║       🚀 GitHub Pages 一键部署 · 新手友好版       ║" -ForegroundColor Cyan
Write-Host "╚" -NoNewline
Write-Host "═════════════════════════════════════════════════" -NoNewline
Write-Host "╝" -ForegroundColor White
Write-Host ""

# ═══════════════════════════════════════════════
#  ─── 小工具函数 ───
# ═══════════════════════════════════════════════
function Wait-Enter {
    param([string]$Tip = "按回车继续...")
    Write-Host ""
    Read-Host $Tip | Out-Null
}

function Open-Url {
    param([string]$Url)
    try {
        Start-Process $Url
    } catch {
        Write-Host "  📎 请手动打开: $Url" -ForegroundColor Gray
    }
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ═══════════════════════════════════════════════
#  ─── 引导步骤 1/5: 检查 & 安装 Git ───
# ═══════════════════════════════════════════════
function Ensure-Git {
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  🔍 第 1 步：检查 Git 环境" -ForegroundColor White
    Write-Host ""

    if (Test-Command "git") {
        $ver = (git --version 2>$null) -replace '^git version\s+', ''
        Write-Host "  ✅ 已安装 Git: $ver" -ForegroundColor Green
    } else {
        Write-Host "  ❌ 未检测到 Git" -ForegroundColor Red
        Write-Host ""
        Write-Host "  💡 安装方式三选一：" -ForegroundColor Yellow
        Write-Host "     [1] 用 winget 自动安装 (推荐，Windows 11自带)" -ForegroundColor Gray
        Write-Host "         命令: winget install --id Git.Git -e --source winget" -ForegroundColor Gray
        Write-Host "     [2] 官网下载安装包：" -ForegroundColor Gray
        Write-Host "         https://git-scm.com/download/win" -ForegroundColor Gray
        Write-Host "     [3] 用 scoop 安装: scoop install git" -ForegroundColor Gray
        Write-Host ""

        $auto = Read-Host "  是否尝试用 winget 自动安装？(Y/n，默认 Y)"
        if ($auto -ne "n" -and $auto -ne "N") {
            if (Test-Command "winget") {
                Write-Host "  📦 正在调用 winget 安装 Git，请在弹出窗口确认..." -ForegroundColor Yellow
                try {
                    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
                    Write-Host "  ⏳ 安装完成，正在刷新 PATH..." -ForegroundColor Yellow
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                                [System.Environment]::GetEnvironmentVariable("Path","User")
                    if (Test-Command "git") {
                        Write-Host "  ✅ Git 安装成功！" -ForegroundColor Green
                    } else {
                        Write-Host "  ⚠️  未检测到新安装的 Git，请关闭本脚本重新运行，或重启 PowerShell" -ForegroundColor Yellow
                        Wait-Enter
                        exit 1
                    }
                } catch {
                    Write-Host "  ❌ winget 安装失败: $_" -ForegroundColor Red
                    Write-Host "  请手动下载安装: https://git-scm.com/download/win" -ForegroundColor Yellow
                    Open-Url "https://git-scm.com/download/win"
                    Wait-Enter "安装完成后按回车继续..."
                    if (-not (Test-Command "git")) {
                        Write-Host "  ❌ 仍然没检测到 Git，请重启脚本" -ForegroundColor Red
                        Wait-Enter
                        exit 1
                    }
                }
            } else {
                Write-Host "  ⚠️  系统没有 winget，请手动下载安装 Git" -ForegroundColor Yellow
                Open-Url "https://git-scm.com/download/win"
                Wait-Enter "安装完成后按回车继续..."
                if (-not (Test-Command "git")) {
                    Write-Host "  ❌ 仍然没检测到 Git，请重启脚本" -ForegroundColor Red
                    Wait-Enter
                    exit 1
                }
            }
        } else {
            Write-Host "  请自行安装 Git 后重新运行脚本" -ForegroundColor Yellow
            Wait-Enter
            exit 1
        }
    }

    # ── 检查 Git 用户名/邮箱配置 ──
    $gitName = git config --global user.name 2>$null
    $gitEmail = git config --global user.email 2>$null
    if ([string]::IsNullOrWhiteSpace($gitName) -or [string]::IsNullOrWhiteSpace($gitEmail)) {
        Write-Host ""
        Write-Host "  ⚠️  Git 还没配置用户名/邮箱（提交需要）" -ForegroundColor Yellow
        Write-Host "  请填写以下信息（会保存到 Git 全局配置）："
        Write-Host ""
        if ([string]::IsNullOrWhiteSpace($gitName)) {
            $inputName = Read-Host "  ① 你的 GitHub 用户名/昵称"
            if ([string]::IsNullOrWhiteSpace($inputName)) { $inputName = "GitHub User" }
            git config --global user.name $inputName
        }
        if ([string]::IsNullOrWhiteSpace($gitEmail)) {
            $inputEmail = Read-Host "  ② 你的 GitHub 绑定邮箱"
            while ($inputEmail -notmatch '^\S+@\S+\.\S+$') {
                Write-Host "     ❌ 邮箱格式不对，重新输入" -ForegroundColor Red
                $inputEmail = Read-Host "  ② 你的 GitHub 绑定邮箱"
            }
            git config --global user.email $inputEmail
        }
        Write-Host "  ✅ Git 身份已保存：$(git config --global user.name) <$(git config --global user.email)>" -ForegroundColor Green
    } else {
        Write-Host "  👤 Git 身份: $gitName <$gitEmail>" -ForegroundColor Gray
    }
    Write-Host ""
}

# ═══════════════════════════════════════════════
#  ─── 引导步骤 2/5: 检查 & 安装 GitHub CLI (gh) ───
# ═══════════════════════════════════════════════
function Ensure-GhCli {
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  🔍 第 2 步：检查 GitHub CLI (gh) 工具" -ForegroundColor White
    Write-Host ""

    if (Test-Command "gh") {
        $ver = (gh --version 2>$null) -split "`n" | Select-Object -First 1
        Write-Host "  ✅ 已安装 GitHub CLI: $ver" -ForegroundColor Green
    } else {
        Write-Host "  ❌ 未检测到 GitHub CLI (gh)" -ForegroundColor Red
        Write-Host "     gh 是 GitHub 官方的命令行工具，用来登录和操作仓库" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  💡 安装方式三选一：" -ForegroundColor Yellow
        Write-Host "     [1] winget 自动安装 (推荐): winget install GitHub.cli" -ForegroundColor Gray
        Write-Host "     [2] 官网下载: https://cli.github.com/" -ForegroundColor Gray
        Write-Host "     [3] scoop 安装: scoop install gh" -ForegroundColor Gray
        Write-Host ""

        $auto = Read-Host "  是否尝试用 winget 自动安装？(Y/n，默认 Y)"
        if ($auto -ne "n" -and $auto -ne "N") {
            if (Test-Command "winget") {
                Write-Host "  📦 正在调用 winget 安装 GitHub CLI..." -ForegroundColor Yellow
                try {
                    winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
                    Write-Host "  ⏳ 安装完成，正在刷新 PATH..." -ForegroundColor Yellow
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                                [System.Environment]::GetEnvironmentVariable("Path","User")
                    if (Test-Command "gh") {
                        Write-Host "  ✅ GitHub CLI 安装成功！" -ForegroundColor Green
                    } else {
                        Write-Host "  ⚠️  未检测到 gh，请关闭脚本重新运行" -ForegroundColor Yellow
                        Wait-Enter
                        exit 1
                    }
                } catch {
                    Write-Host "  ❌ winget 安装失败，请手动下载：https://cli.github.com/" -ForegroundColor Red
                    Open-Url "https://cli.github.com/"
                    Wait-Enter "安装完成后按回车继续..."
                    if (-not (Test-Command "gh")) {
                        Write-Host "  ❌ 仍然没检测到 gh，请重启脚本" -ForegroundColor Red
                        Wait-Enter
                        exit 1
                    }
                }
            } else {
                Write-Host "  ⚠️  没有 winget，请手动下载：https://cli.github.com/" -ForegroundColor Yellow
                Open-Url "https://cli.github.com/"
                Wait-Enter "安装完成后按回车继续..."
                if (-not (Test-Command "gh")) {
                    Write-Host "  ❌ 仍然没检测到 gh，请重启脚本" -ForegroundColor Red
                    Wait-Enter
                    exit 1
                }
            }
        } else {
            Write-Host "  请自行安装 GitHub CLI 后重新运行脚本" -ForegroundColor Yellow
            Wait-Enter
            exit 1
        }
    }
    Write-Host ""
}

# ═══════════════════════════════════════════════
#  ─── 引导步骤 3/5: GitHub 登录 + 账户切换 ───
# ═══════════════════════════════════════════════
function Ensure-GhLoggedIn {
    param([switch]$ForceRelogin)
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  🔐 第 3 步：登录 GitHub 账户" -ForegroundColor White
    Write-Host ""

    # 强制重新登录时先登出
    if ($ForceRelogin) {
        Write-Host "  🚪 正在登出当前账户..." -ForegroundColor Gray
        gh auth logout --hostname github.com 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
    }

    $authOk = $false
    $status = gh auth status 2>&1
    if ($LASTEXITCODE -eq 0 -and -not $ForceRelogin) {
        $authOk = $true
        Write-Host "  ✅ 检测到已登录的 GitHub 账户" -ForegroundColor Green
    } else {
        Write-Host "  ❌ 还没登录 GitHub，接下来开始登录流程" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  💡 即将执行: gh auth login" -ForegroundColor Cyan
        Write-Host "  请按提示操作（建议选项：" -ForegroundColor Gray
        Write-Host "     • 主机: GitHub.com" -ForegroundColor Gray
        Write-Host "     • 协议: HTTPS" -ForegroundColor Gray
        Write-Host "     • 登录方式: 浏览器登录 (Login with a web browser) 最省事" -ForegroundColor Gray
        Write-Host "     • 复制一次性码 → 浏览器粘贴 → 授权 → 回来回车 )" -ForegroundColor Gray
        Write-Host ""
        Wait-Enter "准备好后按回车开始登录..."
        Write-Host ""

        # 直接调用 gh auth login 交互
        gh auth login --hostname github.com --git-protocol https --web

        # 再次检查
        $status = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            $authOk = $true
            Write-Host ""
            Write-Host "  ✅ GitHub 登录成功！" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "  ❌ 登录失败，错误信息:" -ForegroundColor Red
            Write-Host "  $status" -ForegroundColor Red
            $retry = Read-Host "  要重试吗？(Y/n)"
            if ($retry -ne "n") {
                return Ensure-GhLoggedIn -ForceRelogin
            } else {
                Wait-Enter
                exit 1
            }
        }
    }

    # 拉取用户信息并显示
    try {
        $script:GH_USER = gh api user --jq .login 2>$null
        $userName = gh api user --jq .name 2>$null
        $userEmail = gh api user --jq .email 2>$null
        $userBio = gh api user --jq .bio 2>$null
        $userFollowers = gh api user --jq .followers 2>$null
        $userFollowing = gh api user --jq .following 2>$null
        $userRepos = gh api user --jq .public_repos 2>$null
        $userCreated = gh api user --jq .created_at 2>$null
        $avatar = gh api user --jq .avatar_url 2>$null

        Write-Host ""
        Write-Host "  ╭─────────────────────────────────────────╮" -ForegroundColor Cyan
        Write-Host "  │  🧑‍💻  当前连接的 GitHub 账户              │" -ForegroundColor Cyan
        Write-Host "  ├─────────────────────────────────────────┤" -ForegroundColor Cyan
        if ($userName -and $userName -ne "null") {
            Write-Host "  │  昵称:   $userName" -ForegroundColor White
        }
        Write-Host "  │  用户名: @$GH_USER" -ForegroundColor White
        if ($userEmail -and $userEmail -ne "null") {
            Write-Host "  │  邮箱:   $userEmail" -ForegroundColor Gray
        }
        if ($userBio -and $userBio -ne "null") {
            $bioLines = $userBio -split "`n"
            foreach ($line in $bioLines[0..1]) {
                if ($line) { Write-Host "  │  简介:   $line" -ForegroundColor Gray }
            }
        }
        Write-Host "  │  仓库:   $userRepos 公开仓库" -ForegroundColor Gray
        Write-Host "  │  粉丝:   $userFollowers 关注者 · $userFollowing 关注中" -ForegroundColor Gray
        if ($userCreated -and $userCreated -ne "null") {
            try {
                $created = [DateTime]::Parse($userCreated)
                Write-Host "  │  注册于: $($created.ToString('yyyy年MM月'))" -ForegroundColor Gray
            } catch {}
        }
        Write-Host "  │  主页:   https://github.com/$GH_USER" -ForegroundColor Blue
        Write-Host "  ╰─────────────────────────────────────────╯" -ForegroundColor Cyan
        Write-Host ""
    } catch {
        Write-Host "  ✅ 已登录: @$GH_USER" -ForegroundColor Green
    }

    # 问用户要不要切换账号
    $switch = Read-Host "  使用这个账号继续？(Y = 继续 / s = 切换账号，默认 Y)"
    if ($switch -eq "s" -or $switch -eq "S") {
        Write-Host "  🔄 准备切换账号..." -ForegroundColor Yellow
        Write-Host ""
        return Ensure-GhLoggedIn -ForceRelogin
    }
    Write-Host ""
    return $true
}

# ═══════════════════════════════════════════════
#  ─── 执行：环境检查全套 ───
# ═══════════════════════════════════════════════
Ensure-Git
Ensure-GhCli
Ensure-GhLoggedIn

Write-Host "─────────────────────────────────────────────────" -ForegroundColor Green
Write-Host "  🎉  环境准备完毕！开始部署流程..." -ForegroundColor Green
Write-Host "─────────────────────────────────────────────────" -ForegroundColor Green
Write-Host ""
Start-Sleep -Milliseconds 800

# ═══════════════════════════════════════════════
#  ─── 获取当前文件夹名 + 拼音转换 ───
# ═══════════════════════════════════════════════
$FOLDER_NAME_RAW = Split-Path -Leaf $PWD.Path
Write-Host "📂 当前文件夹: $FOLDER" -ForegroundColor Yellow

$PINYIN_MAP = @{
    "强化学习" = "qianghuaxuexi"; "机器学习" = "jiqixuexi"
    "深度学习" = "shenduxuexi";  "自然语言" = "ziranyuyan"
    "计算机视觉" = "jisuanjishijue"; "数据科学" = "shujukexue"
    "人工智能" = "rengongzhineng"; "每日总结" = "meirizongjie"
    "学习笔记" = "xuexibiji";    "暑假计划" = "shujiajihua"
    "暑假" = "shujia";          "校园" = "xiaoyuan"
    "指南" = "zhinan";          "项目" = "xiangmu"
    "部署" = "bushu";           "测试" = "ceshi"
    "文档" = "wendang";         "工具" = "gongju"
    "代码" = "daima";           "算法" = "suanfa"
    "模型" = "moxing";          "数据" = "shuju"
    "分析" = "fenxi";           "教程" = "jiaocheng"
    "首页" = "shouye";          "博客" = "boke"
    "总结" = "zongjie";         "笔记" = "biji"
}
$NAME = $FOLDER_NAME_RAW
if ($NAME -match '[\u4e00-\u9fff]') {
    $oldName = $NAME
    foreach ($key in $PINYIN_MAP.Keys) {
        $NAME = $NAME -replace $key, $PINYIN_MAP[$key]
    }
    if ($NAME -match '[\u4e00-\u9fff]') {
        $NAME = $NAME -replace '[\u4e00-\u9fff]+', 'repo'
    }
    Write-Host "📝 文件夹名含中文，已转为拼音: $oldName → $NAME" -ForegroundColor Yellow
}
Write-Host ""

# ─── 部署模式相关全局变量 ───
$DEPLOY_MODE = $null
$REPO_NAME = $null
$SUBFOLDER = $null
$DISPLAY_PATH = $NAME

# ═══════════════════════════════════════════════
#  ─── 配置读写函数 ───
# ═══════════════════════════════════════════════
function Save-Config {
    param([string]$Mode, [string]$Repo, [string]$Sub = "")
    $config = @{
        mode = $Mode; repo = $Repo; subfolder = $Sub
        display_path = $DISPLAY_PATH
        gh_user = $GH_USER
        saved_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $config | ConvertTo-Json -Depth 3 | Set-Content $CONFIG_FILE -Encoding UTF8
}
function Get-Config {
    if (Test-Path $CONFIG_FILE) {
        try { return Get-Content $CONFIG_FILE -Raw | ConvertTo-Json -Depth 5 } catch { return $null }
    }
    return $null
}

# ═══════════════════════════════════════════════
#  ─── 通用 Push（重试 + 冲突处理） ───
# ═══════════════════════════════════════════════
function Push-Git {
    param([string]$TargetBranch = $BRANCH)
    Write-Host "📤 正在推送到 GitHub ..." -ForegroundColor Yellow

    $maxRetries = 3
    for ($retry = 1; $retry -le $maxRetries; $retry++) {
        if ($retry -gt 1) {
            Write-Host "  ⏳ 第 $retry 次重试 push ..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
        $pushResult = git push -u origin $TargetBranch 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            Write-Host "✅ 推送成功！" -ForegroundColor Green
            return $true
        }
        Write-Host "⚠️  git push 失败 (退出码: $exitCode)" -ForegroundColor Yellow
        Write-Host "   错误信息: $pushResult" -ForegroundColor Red
        if ($pushResult -match "failed to push some refs") {
            Write-Host "   ➜ 远程有新提交，执行 pull --rebase 合并..." -ForegroundColor Yellow
            git pull --rebase origin $TargetBranch 2>&1 | Out-Null
        }
        if ($pushResult -match "Repository not found" -or $pushResult -match "ERROR: Repository") {
            Write-Host "   ➜ 仓库不存在或无权限，请检查账号与仓库名" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "❌ $maxRetries 次推送均失败 😢" -ForegroundColor Red
    Write-Host "  可能原因与解决方法：" -ForegroundColor Yellow
    Write-Host "   1. 网络问题 → 开代理，或直接在终端运行 git push 手动推" -ForegroundColor Gray
    Write-Host "   2. 权限问题 → 运行 gh auth login 重新登录授权" -ForegroundColor Gray
    Write-Host "   3. 仓库不存在 → 浏览器打开 https://github.com/$GH_USER/$REPO_NAME 检查" -ForegroundColor Gray
    Write-Host "   4. SSH/证书问题 → 手动: git remote -v 看地址对不对" -ForegroundColor Gray
    Write-Host ""
    return $false
}

# ═══════════════════════════════════════════════
#  ─── 启用 Pages ───
# ═══════════════════════════════════════════════
function Enable-Pages {
    param([string]$Repo = $REPO_NAME)
    Write-Host ""
    Write-Host "🌐 正在启用 GitHub Pages ..." -ForegroundColor Yellow
    try {
        gh api "repos/${GH_USER}/${Repo}/pages" -X POST `
            -f source[branch]=$BRANCH -f source[path]="/" 2>$null | Out-Null
        Write-Host "✅ GitHub Pages 已开启！首次构建约 1-2 分钟" -ForegroundColor Green
    } catch {
        try {
            # 再试一次 GET，看看是不是已经开启了
            gh api "repos/${GH_USER}/${Repo}/pages" 2>$null | Out-Null
            Write-Host "✅ GitHub Pages 已是开启状态" -ForegroundColor Green
        } catch {
            Write-Host "⚠️  自动开启失败，请手动设置：" -ForegroundColor Yellow
            Write-Host "   1. 打开仓库 Settings → Pages" -ForegroundColor Gray
            Write-Host "   2. Source 选择: Branch = $BRANCH, Folder = / (root)" -ForegroundColor Gray
            Write-Host "   3. Save 后等 1 分钟" -ForegroundColor Gray
            Open-Url "https://github.com/$GH_USER/$Repo/settings/pages"
        }
    }
}

# ═══════════════════════════════════════════════
#  ─── 部署完成展示 ───
# ═══════════════════════════════════════════════
function Show-Result {
    Write-Host ""
    Write-Host "╔═════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                🎉  部署完成！                    ║" -ForegroundColor Green
    Write-Host "╚═════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  📍 访问地址（复制到浏览器打开）:" -ForegroundColor White
    Write-Host "     https://$GH_USER.github.io/$DISPLAY_PATH/" -ForegroundColor Green
    Write-Host ""
    if ($DEPLOY_MODE -eq "repo") {
        Write-Host "  📂 仓库地址:" -ForegroundColor White
        Write-Host "     https://github.com/$GH_USER/$REPO_NAME" -ForegroundColor Blue
    } else {
        Write-Host "  📂 仓库位置（主仓库子目录）:" -ForegroundColor White
        Write-Host "     https://github.com/$GH_USER/$REPO_NAME/tree/$BRANCH/$SUBFOLDER" -ForegroundColor Blue
    }
    Write-Host ""
    Write-Host "  💡 小贴士:" -ForegroundColor Yellow
    Write-Host "     • 首次打开显示 404 → 等 1-2 分钟让 GitHub 构建完" -ForegroundColor Gray
    Write-Host "     • 样式不对/没更新 → 浏览器 Ctrl+F5 强制刷新缓存" -ForegroundColor Gray
    Write-Host "     • 要更新内容 → 再次运行本脚本即可" -ForegroundColor Gray
    Write-Host "     • 想切换部署模式 → 删除 .deploy-config.json 再跑脚本" -ForegroundColor Gray
    Write-Host ""
    $open = Read-Host "  要在浏览器打开访问地址吗？(Y/n，默认 Y)"
    if ($open -ne "n" -and $open -ne "N") {
        Open-Url "https://$GH_USER.github.io/$DISPLAY_PATH/"
    }
}

# ═══════════════════════════════════════════════
#  PushOnly 模式（快速更新）
# ═══════════════════════════════════════════════
if ($PushOnly) {
    $cfg = Get-Config
    if ($cfg -and $cfg.mode) {
        $DEPLOY_MODE = $cfg.mode
        $REPO_NAME = $cfg.repo
        $SUBFOLDER = $cfg.subfolder
        if ($cfg.display_path) { $DISPLAY_PATH = $cfg.display_path }
        Write-Host "📋 读取上次配置 → $(if ($DEPLOY_MODE -eq 'repo') {'独立仓库模式'} else {'主仓库子文件夹模式'})" -ForegroundColor Green
    } else {
        Write-Host "⚠️  无配置文件，默认独立仓库模式" -ForegroundColor Yellow
        $DEPLOY_MODE = "repo"
        $REPO_NAME = $NAME
    }
    Write-Host ""

    # 账号校验：配置里的账号和当前登录账号一致吗？
    if ($cfg -and $cfg.gh_user -and $cfg.gh_user -ne $GH_USER) {
        Write-Host "⚠️  警告：当前账号 @$GH_USER 和配置中的账号 @$($cfg.gh_user) 不同！" -ForegroundColor Yellow
        $go = Read-Host "  继续用 @$GH_USER 推送吗？(Y/n)"
        if ($go -eq "n") { exit 0 }
        Write-Host ""
    }

    # ── 模式一：独立仓库 PushOnly ──
    if ($DEPLOY_MODE -eq "repo") {
        $hasChanges = git status --porcelain | Out-String
        if (-not [string]::IsNullOrWhiteSpace($hasChanges)) {
            git add .
            git commit -m "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            if ($LASTEXITCODE -ne 0) {
                git commit --allow-empty -m "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            }
            Write-Host "✅ 本地提交完成" -ForegroundColor Green
        } else {
            git commit --allow-empty -m "Re-deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            Write-Host "⏭️  无新改动，空提交触发 Pages 重建" -ForegroundColor Gray
        }
        if (Push-Git) {
            Enable-Pages -Repo $REPO_NAME
            Show-Result
        }
        Write-Host ""
        Write-Host "⏎ 终端保持打开..." -ForegroundColor Gray
        exit
    }

    # ── 模式二：主仓库子文件夹 PushOnly ──
    if ($DEPLOY_MODE -eq "subfolder") {
        Write-Host "🔄 子文件夹快速更新模式" -ForegroundColor Cyan
        Write-Host "   主仓库: $GH_USER/$REPO_NAME · 子目录: /$SUBFOLDER/" -ForegroundColor Gray
        Write-Host ""

        $tmpDir = Join-Path $env:TEMP "gh-deploy-$([guid]::NewGuid().ToString('N'))"
        $mainRepoUrl = "https://github.com/${GH_USER}/${REPO_NAME}.git"

        try {
            Write-Host "📥 克隆主仓库 $REPO_NAME (浅克隆，仅最近一次提交)..." -ForegroundColor Yellow
            git clone --depth 1 -b $BRANCH $mainRepoUrl $tmpDir 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "⚠️  克隆失败，创建临时本地仓库..." -ForegroundColor Yellow
                New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
                Set-Location $tmpDir
                git init 2>$null; git branch -M $BRANCH 2>$null
                git remote add origin $mainRepoUrl 2>$null
                Set-Location $FOLDER
            }

            $targetDir = Join-Path $tmpDir $SUBFOLDER
            if (Test-Path $targetDir) {
                Write-Host "🗑️  清空旧子目录 /$SUBFOLDER/ ..." -ForegroundColor Gray
                Get-ChildItem $targetDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            Write-Host "📋 复制文件到子目录 /$SUBFOLDER/ ..." -ForegroundColor Yellow
            Get-ChildItem $FOLDER -Force | Where-Object {
                $_.Name -notin @(".git", $CONFIG_FILE, "deploy.ps1", "deploy.bat", "push_err.txt") -and
                $_.Name -notlike "*.ps1"
            } | ForEach-Object {
                $dest = Join-Path $targetDir $_.Name
                if ($_.PSIsContainer) { Copy-Item $_.FullName $dest -Recurse -Force }
                else { Copy-Item $_.FullName $dest -Force }
            }

            Set-Location $tmpDir
            $hasChanges = git status --porcelain | Out-String
            if (-not [string]::IsNullOrWhiteSpace($hasChanges)) {
                git add .
                git commit -m "Update $SUBFOLDER`: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
                Write-Host "✅ 主仓库本地提交完成" -ForegroundColor Green
            } else {
                git commit --allow-empty -m "Re-deploy $SUBFOLDER`: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
                Write-Host "⏭️  内容无变化，空提交触发重建" -ForegroundColor Gray
            }
            $pushOk = Push-Git
            Set-Location $FOLDER

            if ($pushOk) {
                Enable-Pages -Repo $REPO_NAME
                Show-Result
            }
        } finally {
            if (Test-Path $tmpDir) {
                Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "🧹 临时文件已清理" -ForegroundColor Gray
            }
        }
        Write-Host ""
        Write-Host "⏎ 终端保持打开..." -ForegroundColor Gray
        exit
    }
}

# ═══════════════════════════════════════════════
#  首次部署：模式选择
# ═══════════════════════════════════════════════

# 读取已有配置 & 校验账号
$existingCfg = Get-Config
if ($existingCfg -and $existingCfg.mode) {
    Write-Host "📋 检测到上次部署配置" -ForegroundColor Cyan
    if ($existingCfg.gh_user) { Write-Host "   账号: @$($existingCfg.gh_user)" -ForegroundColor Gray }
    Write-Host "   模式: $(if ($existingCfg.mode -eq 'repo') {'独立仓库模式'} else {'主仓库子文件夹模式'})" -ForegroundColor Gray
    if ($existingCfg.mode -eq "subfolder") {
        Write-Host "   主仓库: $GH_USER/$($existingCfg.repo) · 子目录: /$($existingCfg.subfolder)/" -ForegroundColor Gray
    } else {
        Write-Host "   仓库: $GH_USER/$($existingCfg.repo)" -ForegroundColor Gray
    }
    # 账号不一致提示
    if ($existingCfg.gh_user -and $existingCfg.gh_user -ne $GH_USER) {
        Write-Host ""
        Write-Host "   ⚠️  当前账号是 @$GH_USER，与配置中的 @$($existingCfg.gh_user) 不一致" -ForegroundColor Yellow
    }
    Write-Host ""
    $reuse = Read-Host "  沿用此配置？(Y = 沿用 / n = 重新选择，默认 Y)"
    if ($reuse -ne "n" -and $reuse -ne "N") {
        $DEPLOY_MODE = $existingCfg.mode
        $REPO_NAME = $existingCfg.repo
        $SUBFOLDER = $existingCfg.subfolder
        if ($existingCfg.display_path) { $DISPLAY_PATH = $existingCfg.display_path }
    }
    Write-Host ""
}

# 没沿用配置 → 让用户选模式
if (-not $DEPLOY_MODE) {
    $MAIN_REPO_SUGGEST = "${GH_USER}.github.io"
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  🎯 选择 GitHub Pages 部署模式" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] 独立仓库模式 (默认，推荐新手)" -ForegroundColor Cyan
    Write-Host "      ├─ 创建独立仓库:  $GH_USER/$NAME" -ForegroundColor Gray
    Write-Host "      ├─ 当前文件夹内容 → 仓库根目录" -ForegroundColor Gray
    Write-Host "      └─ 访问:          https://$GH_USER.github.io/$NAME/" -ForegroundColor Green
    Write-Host "      💡 优点：仓库独立，互不影响，删项目直接删仓库" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [2] 主仓库子文件夹模式" -ForegroundColor Cyan
    Write-Host "      ├─ 使用主页仓库:  $GH_USER/$MAIN_REPO_SUGGEST" -ForegroundColor Gray
    Write-Host "      ├─ 上传到子目录:  /$NAME/" -ForegroundColor Gray
    Write-Host "      └─ 访问:          https://$GH_USER.github.io/$NAME/  (地址和上面一样！)" -ForegroundColor Green
    Write-Host "      💡 优点：只有一个仓库，所有项目分类放子文件夹" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-Host "  请选择 (1/2，直接回车默认 1)"

    if ($choice -eq "2") {
        $DEPLOY_MODE = "subfolder"
        $REPO_NAME = $MAIN_REPO_SUGGEST
        $SUBFOLDER = $NAME
        Write-Host ""
        Write-Host "✅ 已选: 主仓库子文件夹模式 → $MAIN_REPO_SUGGEST/$NAME/" -ForegroundColor Green
    } else {
        $DEPLOY_MODE = "repo"
        $REPO_NAME = $NAME
        $SUBFOLDER = ""
        Write-Host ""
        Write-Host "✅ 已选: 独立仓库模式 → $GH_USER/$NAME" -ForegroundColor Green
    }
    Write-Host ""

    # 保存配置
    Save-Config -Mode $DEPLOY_MODE -Repo $REPO_NAME -Sub $SUBFOLDER
    Write-Host "💾 配置已保存到 .deploy-config.json（下次自动沿用，删掉可重选）" -ForegroundColor Gray
    Write-Host ""
}

# 部署预告
Write-Host "即将部署："
Write-Host "  访问地址: https://$GH_USER.github.io/$DISPLAY_PATH/" -ForegroundColor Cyan
if ($DEPLOY_MODE -eq "repo") {
    Write-Host "  部署方式: 独立仓库 $GH_USER/$REPO_NAME" -ForegroundColor Gray
} else {
    Write-Host "  部署方式: 主仓库 $GH_USER/$REPO_NAME 下的子目录 /$SUBFOLDER/" -ForegroundColor Gray
}
Write-Host ""
Write-Host "⏳ 3秒后开始部署..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
Write-Host ""

# ═══════════════════════════════════════════════
#  分支 A：独立仓库模式
# ═══════════════════════════════════════════════
if ($DEPLOY_MODE -eq "repo") {
    if (Test-Path ".git") {
        $remote = git remote get-url origin 2>$null
        if ($remote) {
            Write-Host "🔄 检测到已有 Git 仓库 & 远程配置，进入快速更新..." -ForegroundColor Green
            & $PSCommandPath -PushOnly
            exit $LASTEXITCODE
        }
    }

    Write-Host "🚀 创建 GitHub 仓库 $GH_USER/$REPO_NAME ..." -ForegroundColor Yellow
    gh repo create $REPO_NAME --public --description "Deployed from $FOLDER via deploy.ps1" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  仓库可能已存在，继续使用" -ForegroundColor Yellow
    } else {
        Write-Host "✅ 仓库创建成功！" -ForegroundColor Green
    }

    if (-not (Test-Path ".git")) {
        Write-Host "🔧 初始化 Git 本地仓库..." -ForegroundColor Yellow
        git init 2>$null
        git branch -M $BRANCH 2>$null
    }

    # .gitignore
    $ignoreItems = @(".git", "deploy.bat", "deploy.ps1", "push_err.txt", $CONFIG_FILE)
    if (-not (Test-Path ".gitignore")) {
        $ignoreItems | Set-Content ".gitignore"
    } else {
        $cur = Get-Content ".gitignore" -Raw
        if ($cur -notmatch [regex]::Escape($CONFIG_FILE)) { Add-Content ".gitignore" $CONFIG_FILE }
    }

    Write-Host "📝 暂存 & 提交代码..." -ForegroundColor Yellow
    git add .
    $commitMsg = "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    git commit -m $commitMsg 2>$null
    if ($LASTEXITCODE -ne 0) {
        git commit --allow-empty -m $commitMsg 2>$null
    }
    Write-Host "✅ 本地提交完成" -ForegroundColor Green

    $remote = git remote get-url origin 2>$null
    if (-not $remote) {
        git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
    }

    if (Push-Git) {
        Enable-Pages -Repo $REPO_NAME
        Show-Result
    }
    Write-Host ""
    Write-Host "⏎ 终端保持打开..." -ForegroundColor Gray
    exit
}

# ═══════════════════════════════════════════════
#  分支 B：主仓库子文件夹模式
# ═══════════════════════════════════════════════
if ($DEPLOY_MODE -eq "subfolder") {
    $tmpDir = Join-Path $env:TEMP "gh-deploy-$([guid]::NewGuid().ToString('N'))"
    $mainRepoUrl = "https://github.com/${GH_USER}/${REPO_NAME}.git"

    try {
        Write-Host "🚀 确保主仓库 $GH_USER/$REPO_NAME 存在..." -ForegroundColor Yellow
        gh repo create $REPO_NAME --public --description "GitHub Pages 主站点 (${GH_USER}.github.io)" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✅ 主仓库已存在" -ForegroundColor Green
        } else {
            Write-Host "✅ 主仓库创建成功！" -ForegroundColor Green
        }

        Write-Host "📥 准备主仓库工作区..." -ForegroundColor Yellow
        $cloned = $false
        git clone --depth 1 -b $BRANCH $mainRepoUrl $tmpDir 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $tmpDir ".git"))) {
            $cloned = $true
            Write-Host "✅ 主仓库已拉取到本地（最近一次提交）" -ForegroundColor Green
        } else {
            Write-Host "⚠️  主仓库还没内容，初始化临时本地仓库..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
            Set-Location $tmpDir
            git init 2>$null; git branch -M $BRANCH 2>$null
            git remote add origin $mainRepoUrl 2>$null
            if (-not (Test-Path "README.md")) {
                "# $GH_USER · GitHub Pages 主站点`n`n存放所有通过 deploy.ps1 部署的页面项目（子文件夹式管理）。`n" | Set-Content "README.md" -Encoding UTF8
                git add README.md
                git commit -m "Init: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            }
            Set-Location $FOLDER
        }

        $targetDir = Join-Path $tmpDir $SUBFOLDER
        if (Test-Path $targetDir) {
            Write-Host "🗑️  清空旧子目录 /$SUBFOLDER/ ..." -ForegroundColor Gray
            Get-ChildItem $targetDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Write-Host "📋 复制当前文件到主仓库子目录 /$SUBFOLDER/ ..." -ForegroundColor Yellow
        Get-ChildItem $FOLDER -Force | Where-Object {
            $_.Name -notin @(".git", $CONFIG_FILE, "deploy.ps1", "deploy.bat", "push_err.txt") -and
            $_.Name -notlike "*.ps1"
        } | ForEach-Object {
            $dest = Join-Path $targetDir $_.Name
            if ($_.PSIsContainer) { Copy-Item $_.FullName $dest -Recurse -Force }
            else { Copy-Item $_.FullName $dest -Force }
        }
        Write-Host "✅ 复制完成" -ForegroundColor Green

        Write-Host "📝 提交主仓库更新..." -ForegroundColor Yellow
        Set-Location $tmpDir
        $hasChanges = git status --porcelain | Out-String
        if (-not [string]::IsNullOrWhiteSpace($hasChanges)) {
            git add .
            git commit -m "Add/Update $SUBFOLDER`: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            Write-Host "✅ 主仓库本地提交完成" -ForegroundColor Green
        } else {
            git commit --allow-empty -m "Re-deploy $SUBFOLDER`: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            Write-Host "⏭️  内容无变化，空提交触发 Pages 重建" -ForegroundColor Gray
        }
        $pushOk = Push-Git
        Set-Location $FOLDER

        if ($pushOk) {
            Enable-Pages -Repo $REPO_NAME
            Show-Result
        }
    } finally {
        if (Test-Path $tmpDir) {
            Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "🧹 临时克隆目录已清理" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "⏎ 终端保持打开..." -ForegroundColor Gray
    exit
}
