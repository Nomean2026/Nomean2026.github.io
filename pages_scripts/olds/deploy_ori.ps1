<#
.SYNOPSIS
  GitHub Pages 通用部署脚本 (PowerShell版)
  复制到任意文件夹，右键"使用 PowerShell 运行"
  把所在文件夹部署到同名的 GitHub 仓库，并开启 Pages
.PARAMETER PushOnly
  内部使用，仅执行 git push（已有仓库时调用）
#>
param([switch]$PushOnly)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "GitHub Pages 一键部署"

# ─── Banner ───
Write-Host "╔" -NoNewline
Write-Host "══════════════════════════════════════════" -NoNewline
Write-Host "╗" -ForegroundColor White
Write-Host "║        GitHub Pages 一键部署脚本          ║" -ForegroundColor Cyan
Write-Host "╚" -NoNewline
Write-Host "══════════════════════════════════════════" -NoNewline
Write-Host "╝" -ForegroundColor White
Write-Host ""

# ─── 检查 gh ───
if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 未检测到 GitHub CLI (gh)" -ForegroundColor Red
    Write-Host "请先安装: https://cli.github.com/"
    Write-Host "安装后运行: gh auth login"
    exit 1
}

# ─── 检查登录 ───
$status = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 未登录 GitHub CLI" -ForegroundColor Red
    Write-Host "请运行: gh auth login"
    exit 1
}

$GH_USER = gh api user --jq .login 2>$null
Write-Host "✅ 已登录: $GH_USER" -ForegroundColor Green
Write-Host ""

# ─── 获取当前文件夹名作为仓库名 ───
$REPO_NAME = Split-Path -Leaf $PWD.Path
$BRANCH = "main"
$FOLDER = $PWD.Path

Write-Host "📂 当前文件夹: $FOLDER" -ForegroundColor Yellow

# ─── 如果仓库名包含中文字符，转为拼音 ───
$PINYIN_MAP = @{
    "强化学习" = "qianghuaxuexi"
    "机器学习" = "jiqixuexi"
    "深度学习" = "shenduxuexi"
    "自然语言" = "ziranyuyan"
    "计算机视觉" = "jisuanjishijue"
    "数据科学" = "shujukexue"
    "人工智能" = "rengongzhineng"
    "每日总结" = "meirizongjie"
    "学习笔记" = "xuexibiji"
    "项目" = "xiangmu"
    "部署" = "bushu"
    "测试" = "ceshi"
    "文档" = "wendang"
    "工具" = "gongju"
    "代码" = "daima"
    "算法" = "suanfa"
    "模型" = "moxing"
    "数据" = "shuju"
    "分析" = "fenxi"
    "教程" = "jiaocheng"
}
if ($REPO_NAME -match '[\u4e00-\u9fff]') {
    $oldName = $REPO_NAME
    foreach ($key in $PINYIN_MAP.Keys) {
        $REPO_NAME = $REPO_NAME -replace $key, $PINYIN_MAP[$key]
    }
    # 如果仍有未映射的中文字符，用拼音首字母替代
    if ($REPO_NAME -match '[\u4e00-\u9fff]') {
        $REPO_NAME = $REPO_NAME -replace '[\u4e00-\u9fff]+', 'repo'
    }
    Write-Host "📦 原文件夹名含中文，已转为拼音: $oldName → $REPO_NAME" -ForegroundColor Yellow
}
Write-Host "📦 目标仓库: $GH_USER/$REPO_NAME" -ForegroundColor Yellow
Write-Host ""

# ─── 函数：Push ───
function Push-Git {
    Write-Host "📤 正在推送到 GitHub ..." -ForegroundColor Yellow

    $maxRetries = 3
    for ($retry = 1; $retry -le $maxRetries; $retry++) {
        if ($retry -gt 1) {
            Write-Host "  ⏳ 第 $retry 次重试 push ..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
        $pushResult = git push -u origin $BRANCH 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            Write-Host "✅ 推送成功！" -ForegroundColor Green
            return $true
        }
        Write-Host "⚠️  git push 失败 (退出码: $exitCode)" -ForegroundColor Yellow
        Write-Host "   错误信息: $pushResult" -ForegroundColor Red
        if ($pushResult -match "failed to push some refs") {
            Write-Host "   ➜ 远程有冲突，执行 pull --rebase ..." -ForegroundColor Yellow
            git pull --rebase origin $BRANCH 2>&1 | Out-Null
        }
    }
    Write-Host "❌ git push 重试 $maxRetries 次均失败" -ForegroundColor Red
    Write-Host "   最后错误: $pushResult" -ForegroundColor Red
    Write-Host ""
    Write-Host "可能的原因:" -ForegroundColor Yellow
    Write-Host "  1. 网络问题 → 检查代理或直接运行: git push" -ForegroundColor Gray
    Write-Host "  2. 权限问题 → 运行: gh auth login" -ForegroundColor Gray
    Write-Host "  3. 仓库不存在 → 检查: https://github.com/$GH_USER/$REPO_NAME" -ForegroundColor Gray
    Write-Host ""
    return $false
}

# ─── 函数：启用 Pages ───
function Enable-Pages {
    Write-Host ""
    Write-Host "🌐 正在启用 GitHub Pages ..." -ForegroundColor Yellow
    try {
        $result = gh api "repos/${GH_USER}/${REPO_NAME}/pages" -X POST -f source[branch]=$BRANCH -f source[path]="/" 2>$null
        Write-Host "✅ GitHub Pages 已启用！" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Pages 可能已启用，或需手动设置" -ForegroundColor Yellow
        Write-Host "   仓库 Settings > Pages > 选择 main 分支" -ForegroundColor Gray
    }
}

# ─── 函数：显示结果 ───
function Show-Result {
    Write-Host ""
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  🎉  部署完成！" -ForegroundColor White
    Write-Host ""
    Write-Host "  📍 访问地址:" -ForegroundColor White
    Write-Host "  https://$GH_USER.github.io/$REPO_NAME/" -ForegroundColor Green
    Write-Host ""
    Write-Host "  📂 仓库地址:" -ForegroundColor White
    Write-Host "  https://github.com/$GH_USER/$REPO_NAME" -ForegroundColor Blue
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "💡 如果页面显示 404，请等 1-2 分钟让 GitHub 构建完成" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "⏎ 终端保持打开，可继续输入命令..." -ForegroundColor Gray
}

# ─── PushOnly 模式 ───
if ($PushOnly) {
    # 检查是否有未提交更改
    $hasChanges = git status --porcelain | Out-String
    if (-not [string]::IsNullOrWhiteSpace($hasChanges)) {
        git add .
        git commit -m "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
        if ($LASTEXITCODE -ne 0) {
            git commit --allow-empty -m "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
        }
    } else {
        # 没有改动但用户想重新部署 → 空提交触发 Pages 重建
        git commit --allow-empty -m "Re-deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
    }
    if (Push-Git) {
        Enable-Pages
        Show-Result
    }
    Write-Host ""
    Write-Host "⏎ 终端保持打开，可继续输入命令..." -ForegroundColor Gray
    exit
}

# ─── 跳过确认 ───
Write-Host "即将部署为 GitHub Pages 网站："
Write-Host "  https://$GH_USER.github.io/$REPO_NAME/" -ForegroundColor Cyan
Write-Host ""
Write-Host "⏳ 开始部署..."
Write-Host ""

# ─── 已有仓库？直接 PushOnly 子进程 ───
if (Test-Path ".git") {
    $remote = git remote get-url origin 2>$null
    if ($remote) {
        Write-Host "🔄 检测到已有 Git 仓库，直接推送更新..." -ForegroundColor Green
        & $PSCommandPath -PushOnly
        exit $LASTEXITCODE
    }
}

# ─── 创建 GitHub 仓库 ───
Write-Host "🚀 正在创建 GitHub 仓库 $REPO_NAME ..." -ForegroundColor Yellow
gh repo create $REPO_NAME --public --description "Deployed from $FOLDER" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  仓库可能已存在" -ForegroundColor Yellow
} else {
    Write-Host "✅ 仓库创建成功！" -ForegroundColor Green
}

# ─── 初始化 Git ───
if (-not (Test-Path ".git")) {
    Write-Host "🔧 初始化 Git ..." -ForegroundColor Yellow
    git init 2>$null
    git branch -M $BRANCH 2>$null
}

# ─── .gitignore ───
if (-not (Test-Path ".gitignore")) {
    ".git", "deploy.bat", "deploy.ps1", "push_err.txt" | Set-Content ".gitignore"
}

# ─── 首次提交 ───
Write-Host "📝 暂存并提交代码..." -ForegroundColor Yellow
git add .
$commitMsg = "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
git commit -m $commitMsg 2>$null
if ($LASTEXITCODE -ne 0) {
    git commit --allow-empty -m $commitMsg 2>$null
}
Write-Host "✅ 提交成功" -ForegroundColor Green

# ─── 远程 ───
$remote = git remote get-url origin 2>$null
if (-not $remote) {
    git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
}

# ─── 首次 Push ───
if (Push-Git) {
    Enable-Pages
    Show-Result
}
