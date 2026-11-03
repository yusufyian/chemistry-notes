# 化学笔记 · GitHub 托管文档库

以 GitHub 为远端的个人化学知识库。内容以纯 Markdown 存放于 Git 仓库，
经 [Quartz v4](https://github.com/jackyzha0/quartz) 构建为静态站点，
通过 GitHub Pages 发布，可在手机、平板、电脑浏览器直接查阅。

## 快速开始

```bash
./sync.sh                      # 提交并推送全部改动
./sync.sh "补充 Ksp 数据"       # 带自定义提交信息

npx quartz build --serve -d public   # 本地预览（默认 8080 端口）
```

站点地址：<https://yusufyian.github.io/chemistry-notes/>

## 目录结构

```
chemistry-notes/
├── content/                    # 全部笔记源文件（唯一需要手动维护的地方）
│   ├── index.md                # 首页与导航
│   ├── 溶解度与溶度积/          # 按主题分文件夹
│   └── 元素化学/
├── attachments/                # 图片等附件资源
├── templates/                  # 写作模板，不参与发布
├── private/                    # 私密内容，已在 quartz.config.ts 中排除
├── quartz.config.ts            # 站点配置（标题、语言、字体、插件）
├── quartz.layout.ts            # 页面布局配置
├── .github/workflows/deploy.yml # 自动部署流水线
└── sync.sh                     # 一键同步脚本
```

## 写作约定

### 数学与化学式

统一使用 LaTeX，行内 `$...$`，独立成行 `$$...$$`：

```markdown
$K_{sp} = [\mathrm{Ag^+}][\mathrm{Cl^-}]$

$$
\mathrm{Ag_2CO_3(s) \rightleftharpoons 2Ag^+ + CO_3^{2-}}
$$
```

> [!warning] 注意
> `\mathrm{}` 内不要混入中文，KaTeX 会报 `Unicode text character used in math mode` 警告。
> 中文标注写在公式外面，例如 `$\mathrm{2Na_2O_2}$（过量）`。

### 表格

同类数据一律用表格，便于横向对照：

```markdown
| 化合物 | $K_{sp}$ | 备注 |
| --- | --- | --- |
| AgCl | $1.8 \times 10^{-10}$ | 见光变紫 |
```

### 双链

用 `[[笔记名]]` 互连，站点自动生成反向链接与关系图谱：

```markdown
参见 [[常见难溶电解质的溶度积常数]] 与 [[溶度积与水的离子积]]。
```

注意 `[[笔记名]]` 要与文件名完全一致（不含 `.md`），否则会变成无法解析的普通文本。

### 草稿

文件名后加 `_` 前缀或 frontmatter 写 `draft: true`，不会被发布：

```markdown
---
title: 未完成的笔记
draft: true
---
```

## 多端查阅

| 场景 | 方式 |
| --- | --- |
| 手机 / 平板 | 浏览器打开 `yusufyian.github.io/chemistry-notes/` |
| 电脑 | 同上；或用 Obsidian 打开本地 `content/` 目录 |
| 离线 | `git clone` 后本地用 Obsidian 阅读；或下载 Pages 站点镜像 |
| 全文检索 | 站点右上角搜索框（客户端索引，无需联网请求） |

站点为 SPA 模式（`enableSPA: true`），页面切换不重新加载，移动端体验接近原生应用。
建议在手机浏览器上「添加到主屏幕」，即可像 App 一样全屏打开。

## 二进制文件处理策略

**不要把 PDF、图片直接塞进仓库。** 原因：

- GitHub 硬限制：单文件超过 100 MB 直接拒绝推送，超过 50 MB 会警告
- Git 对二进制文件无法增量存储，每次修改都存完整副本，仓库体积线性膨胀
- GitHub 前端渲染 PDF 预览不稳定

### 推荐做法

| 文件类型 | 存放位置 | 笔记中如何引用 |
| --- | --- | --- |
| 论文 PDF | NAS 或对象存储（Cloudflare R2 / 腾讯云 COS） | 写下载链接 |
| 大体积图片 | 同上，或压缩后放 `attachments/` | `![[图片名.png]]` |
| 小体积截图（< 1 MB） | 直接放 `attachments/` | `![[图片名.png]]` |
| 数据文件（CSV 等） | 放 `content/data/`，Git 可正常 diff | 用表格嵌入或链接 |

若确有大文件必须进 Git，Git LFS 免费额度为 1 GB 存储 + 1 GB/月带宽，
且只对新加入的文件生效（历史文件需 `git lfs migrate` 重写，较为麻烦）。

## 备份与安全

**GitHub 就是备份**，但仍建议三层保障：

1. **Git 历史** —— 每次提交都是完整快照，`git log` 可回溯任意版本
2. **本地副本** —— NAS 上跑一个定时 `git pull` 的镜像仓库
3. **异地副本** —— 关键笔记额外导出 PDF 或归档 ZIP

### 私密内容处理

**免费版 GitHub Pages 只支持公开仓库** —— 私有仓库发布 Pages 需要 GitHub Pro（$4/月）。

因此本仓库为公开仓库。请遵守以下规则：

- `private/` 目录已在 `quartz.config.ts` 的 `ignorePatterns` 中排除，不会被发布
- 但 **`.gitignore` 中必须包含 `private/`**，否则文件仍会进入 Git 历史
- 任何敏感数据（密码、密钥、个人信息）不要写入本仓库
- 一旦推送过密钥，立即在 GitHub 撤销该密钥——删除文件并提交**不能**清除历史记录

## 已知环境问题：git 传输层被代理阻断

本机 git clone / push GitHub 仓库时出现 `HTTP2 framing layer` / `CONNECT tunnel failed` 错误。
根因是环境代理（`127.0.0.1:50533`）对 git 的 smart-HTTP 传输层不友好，
但 **GitHub REST API 走同一代理却完全正常** —— 两者协议不同。

### 已内置的解决方案

`sync.sh` 内置了自动降级：git 推送重试 3 次仍失败时，自动切换到 API 通道。

```bash
./sync.sh                    # 自动选择通道，无需干预
./push-via-api.sh "提交信息"  # 强制走 API 通道
```

`push-via-api.sh` 的原理：用 GitHub Git Data API 依次构造 blob → tree → commit，
再更新远端 ref，完全绕开 git 传输层。功能与 `git push` 等价，
但会丢失本地 commit 对象（远端历史由 API 重建，提交信息保留）。

### 其他绕行方式

```bash
# 克隆：强制 HTTP/1.1
git -c http.version=HTTP/1.1 clone <url>

# 克隆：走 GitHub API 下载 tarball
gh api repos/OWNER/REPO/tarball/BRANCH > repo.tar.gz && tar -xzf repo.tar.gz

# 改用 SSH remote（需先配置 SSH 密钥）
git remote set-url origin git@github.com:yusufyian/chemistry-notes.git
```

### 本地 git 状态同步说明

API 通道推送后，本地 `git log` 与远端 SHA 不一致（对象不在本地）。
需要恢复一致时：

```bash
git fetch origin main && git reset --hard origin/main
```

若 fetch 也被阻断，可直接从 API 拉取：

```bash
gh api repos/yusufyian/chemistry-notes/commits/main --jq '.sha'
```

## 技术栈

| 组件 | 版本 / 说明 |
| --- | --- |
| Quartz | v4.5.2（MIT） |
| Node.js | 22（构建要求 >= 22） |
| KaTeX | 0.16.11，数学公式渲染 |
| flexsearch | 客户端全文检索，支持中文 |
| GitHub Actions | push 到 main 自动构建并部署 Pages |

## 许可

Quartz 模板部分为 MIT 许可。笔记内容版权归作者所有。
