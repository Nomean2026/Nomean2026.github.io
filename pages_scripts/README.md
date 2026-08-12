# 页面部署脚本 · 使用说明

本目录 4 个文件的用途与用法：

| 文件 | 用途 | 放在哪 |
|------|------|--------|
| `deploy_all.ps1` | 每个项目的部署脚本（生成 `project.json` + 更新主页 `pages.json` + 推送） | 复制到**每个项目文件夹**，右键"使用 PowerShell 运行" |
| `index.html` | 主页门户（显示所有子项目的 URL：独立 Pages 仓库 + 主项目子文件夹） | 主页仓库 `Nomean2026.github.io` 的根目录 |
| `index_project.html` | **单项目入口页**：扫描自己所在库的文件，渲染层级目录 | 复制到**每个项目文件夹**根目录（可重命名为 `index.html` 作为该项目的入口页） |
| `github-actions-update-pages-json.yml` | 每天自动重建主页 `pages.json`（兜底） | 主页仓库 `Nomean2026.github.io` 的 `.github/workflows/` |

---

## 1. deploy_all.ps1 — 每次部署时自动做两件事

原有功能不变（Git 引导 / gh 登录 / 两种部署模式 / 推送），新增：

1. **生成 `project.json`**：递归扫描当前项目文件夹的文件与目录结构
   - 忽略 `.gitignore` 中匹配的内容
   - 忽略部署时本来就会排除的项（`.git`、`node_modules`、`dist`、`*.log` 等，与上传规则一致）
   - 生成的 `project.json` 随项目一起推送

2. **更新主页 `pages.json`**：推送成功后，通过 `gh api` 直接修改
   `Nomean2026.github.io` 仓库根目录的 `pages.json`，为当前项目写入（或合并更新）条目，
   在原有格式上新增**项目位置信息**：

```json
{
  "name": "minimindTutorials",
  "description": "……",
  "language": "HTML",
  "stargazers_count": 0,
  "updated_at": "2025-07-01T12:00:00Z",
  "repo": "https://github.com/Nomean2026/minimindTutorials",
  "pages": "https://nomean2026.github.io/minimindTutorials/",
  "project_json": "https://nomean2026.github.io/minimindTutorials/project.json",
  "source": "repo"
}
```

- `repo`：仓库位置（子文件夹模式下指向主页仓库中的目录）
- `pages`：页面访问地址
- `project_json`：文件结构索引的地址（主页用它渲染文件树）
- 更新时**保留已有字段**（stars、语言、更新时间等由 Actions 每天刷新）

> 无需 token：脚本用的是已登录的 `gh` 账号，对主页仓库有写权限。
> 若主页仓库暂时不存在或网络失败，会跳过并提示，由 GitHub Actions 兜底补齐。

## 2. index.html — 主页：项目结构从 JSON 获取

- **列表**：优先读取 `/pages.json`（含项目位置信息）；没有时按原逻辑回退
  （GitHub 页面探测 → 本地缓存 → `KNOWN_PAGES` 手动列表）
- **点卡片**：进入项目详情页，展示**文件结构树**（目录可折叠，文件点击打开）
  - 文件树优先从该项目的 `project.json` 获取（`/pages.json` 里的 `project_json` 字段）
  - 没有 `project.json` 时自动回退 GitHub API（`git/trees` 递归文件树）
  - 子文件夹模式的项目（`source: "subfolder"`）会按项目名前缀过滤主页仓库的文件树

## 2.5 index_project.html — 项目入口页（同名 HTML 加载器）

复制到项目文件夹根目录。打开页面会**全屏加载与项目同名的 HTML 文件**
（`./<项目名>.html`，不存在则给出提示），并提供：

- **左上角**：文件目录抽屉 —— 层级目录树，点击其中的 HTML 文件可切换 iframe 内容
- **右下角**：GitHub 仓库 / 返回当前项目主页 / 返回门户首页 三个悬浮按钮
- **仓库来源自动识别**：先当作同名公开仓库 `<owner>/<项目名>`；
  不存在则视为 `<owner>.github.io` 主页仓库下的同名子文件夹
  （独立仓库 / 子文件夹两种部署模式都支持）

**层级目录获取渠道（按顺序回退）**：
1. `project.json` —— 项目根目录，`deploy_all.ps1` 部署时自动生成
   （最完整：含目录/文件/大小/生成时间，且不受 GitHub API 限速影响）
2. GitHub API —— `git/trees/{branch}?recursive=1` 递归文件树（子文件夹模式自动按项目名过滤）

## 3. GitHub Actions — 每天兜底更新 pages.json

**回答你的疑问：放在 `username.github.io` 的 Action，其他仓库的 push 会不会触发它？**
→ **不会。** GitHub Actions 只响应它所在仓库的事件。其他仓库更新时，
本仓库的 workflow 不会被触发（除非对方用 `repository_dispatch` 显式调用）。

所以 `github-actions-update-pages-json.yml` 采用：
- **`schedule`**：每天 02:17 UTC（北京时间 10:17）自动跑一次
- **`workflow_dispatch`**：在 Actions 页面手动点"Run workflow"随时跑

它做的事：
1. 调 GitHub API 列出你名下所有非 fork 仓库，逐个探测是否开启 Pages（`/repos/{user}/{repo}/pages` 返回 200 即开启），写入条目
2. 扫描主页仓库里**根目录含 `index.html` 的文件夹**，识别子文件夹模式的项目
3. 合并去重、按名字排序，写回 `pages.json` 并自动提交推送

**部署步骤**：
1. 把 `github-actions-update-pages-json.yml` 复制到 `Nomean2026.github.io` 仓库的
   `.github/workflows/` 目录，提交推送
2. 首次可到 Actions 页面手动触发一次验证
3. 无需额外配置 secrets（用内置的 `GITHUB_TOKEN`，自动带写权限）

---

## 工作流程总览

```
你改完项目 → 运行 deploy_all.ps1
   ├─ 扫描文件结构 → project.json（随项目推送）
   ├─ git 提交推送项目
   └─ gh api 更新主页 pages.json（含位置信息）→ 主页立即导航
每天凌晨 → GitHub Actions 重建 pages.json（兜底：处理没跑脚本的更新/新仓库）
主页访问 → index.html 读 pages.json → 卡片列表 → 点卡片读 project.json 渲染文件树
```
