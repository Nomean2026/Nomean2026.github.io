# Nomean GitHub Pages 门户

本项目是 [Nomean](https://github.com/Nomean2026) 的 GitHub Pages 统一入口页面。  
它自动扫描您所有的 GitHub Pages 项目，以美观的卡片形式展示，一键跳转访问。

## 功能

- 🔍 **自动扫描** — 通过 GitHub API 获取仓库数据，展示所有 Pages 项目
- 🎨 **精美 UI** — 暗色主题、毛玻璃卡片、渐变色彩、响应式布局
- ⭐ **实时数据** — Stars 数、编程语言、最后更新时间
- 📱 **移动友好** — 完美适配手机 / 平板 / 桌面

## 部署方式

### 方式一：GitHub Pages（推荐）

1. 创建仓库 `Nomean2026.github.io`
2. 将 `index.html` 推送到 `main` 分支
3. 访问 [https://nomean2026.github.io](https://nomean2026.github.io)
4. 在仓库 Settings → Pages 中确认 Source 为 `main` 分支 `/ (root)`

### 方式二：在任意现有 Pages 项目中

将 `index.html` 放入任意已部署 GitHub Pages 的仓库，访问对应 URL 即可。

## 配置

门户数据由 GitHub Actions 自动维护（见 `.github/workflows/github-actions-update-pages-json.yml`）：
每次 push（除 `pages.json` 外）立即扫描、每天 02:17 UTC 兜底，把两类项目写入根目录 `pages.json`：

1. **独立仓库** — 名下开启 Pages 的所有仓库（含 stars / 语言 / 更新时间）
2. **子文件夹** — 本仓库根目录下含 `index.html` 的文件夹

`index.html` 前端以 `/pages.json` 为默认数据源；获取失败时依次回退到本地缓存和内置
`KNOWN_PAGES` 列表（该列表仅为离线兜底，内容应与 `pages.json` 保持同步）。

## License

MIT