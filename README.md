# claude-code-docker

在 Docker 容器里运行 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的自包含启动器 `cca`。

- **一个脚本搞定**:`curl` 装 `cca` 到 PATH,`cd` 到任意项目目录敲 `cca` 即用,不依赖任何项目文件。
- **双鉴权**:默认走 Anthropic **官方订阅**(OAuth 登录);也可用 **第三方中转**(每家一个 profile,`CC_PROFILE=<名> cca` 切换)。
- **中性环境**:容器内非 root 运行,时区/locale 为中性值(UTC / C.UTF-8),不带地区特征。
- **开箱即用**:首次运行自动播种默认配置(中文界面、`dark` 主题、免确认),登录态/历史持久化。

## 快速开始(3 步)

新成员照这三步就能跑起来,细节在下面各章展开:

1. **确认已装 Docker 并已启动** —— 跑 `docker version` 能出版本号即可。没装就先装 [Docker Desktop](https://www.docker.com/products/docker-desktop/) 或 [OrbStack](https://orbstack.dev/)(macOS 推荐 OrbStack,更轻),装完打开让它跑起来。
2. **设镜像地址 `CC_IMAGE`** —— 团队内部镜像地址向管理员获取(或 fork 本仓库自建,见「自己构建镜像」),写进 `~/.zshrc` 一次设置永久生效:
   ```bash
   echo 'export CC_IMAGE=团队给你的镜像地址' >> ~/.zshrc && source ~/.zshrc
   ```
3. **装 `cca` 并首次运行**(见下方「安装」一行命令),然后 `cd` 到任意项目目录敲 `cca`:
   ```bash
   cd ~/你的项目 && cca      # 首次走官方订阅 OAuth 登录;用中转见「第三方中转」
   ```

## 镜像地址

本仓库不写死镜像仓库地址,用之前必须设 `CC_IMAGE` 指向一个真实镜像(二选一):

- **自建**:fork 本仓库,配好 CI(见「自己构建镜像」),推到你自己的 registry。
- **借用现成镜像**:把地址设进环境变量(建议写进 `~/.zshrc`,一次设置永久生效):
  ```bash
  export CC_IMAGE=your-registry.example.com/namespace/claude-code:latest
  ```

> 没设 `CC_IMAGE` 时 `cca` 会直接报错提示。

## 安装(每台机器一行)

```bash
mkdir -p ~/.local/bin && curl -fsSL \
  https://raw.githubusercontent.com/liuy-byte/claude-code-docker/main/cca \
  -o ~/.local/bin/cca && chmod +x ~/.local/bin/cca
# 确保 ~/.local/bin 在 PATH(不在就加:export PATH="$HOME/.local/bin:$PATH")
```

以后升级不用再跑上面这行:`cca update` 会同时拉最新镜像 + 自升级脚本本体。

## 用法

```bash
cd /你的/项目            # cca 把当前所在目录挂进容器,Claude 直接操作宿主机真实文件
cca                     # 默认官方订阅,首次走 OAuth 登录
cca init glm            # 一键生成中转 profile(见「第三方中转」)
CC_PROFILE=glm cca      # 用某家中转
cca -p "把 README 翻译成英文"   # 非交互跑一个任务
cca bash                # 进容器 shell 调试(带 Tab 补全和 ll/gs/gd 等常用别名)
cca doctor              # 自检:docker / CC_IMAGE / profile / ssh / 卷与版本;默认只报问题,-v 看全部
cca update              # 拉取最新镜像 + 自升级 cca 脚本(平时启动不自动更新)
cca -h                  # cca 自身用法(cca --help 则透传显示 claude 的帮助)
```

- **切项目** = `cd` 过去再敲 `cca`;改动实时落在宿主机磁盘上。
- **切中转** = 加 `CC_PROFILE=<名>`。

**顺手加别名**(常用某家时,省得每次写 `CC_PROFILE=`):
```bash
echo "alias ccm='CC_PROFILE=minimax cca'" >> ~/.zshrc   # 之后敲 ccm = 用 MiniMax
```

**首次官方订阅登录**:终端打印一个 URL → 在**宿主机浏览器**打开、用 Claude 账号授权 → 把回调 code 贴回终端。登录态存进官方订阅的专属卷(`claude-config`),之后不用再登。

## 首启自动播种默认配置

新机器首次跑 `cca`(检测为**当前 profile 的卷**不存在)时,写入一套默认 `settings.json`:中文界面、免确认等,完整清单以 `cca` 内 `SEED_JSON` 为准。每个 profile 的卷各播一次,之后开箱即用。

- **幂等 + 不覆盖**:写入是 jq 合并、已有键优先,你后来用 `/theme` 等改的配置不会被回滚。
- **自定义默认**:放一份 `~/.config/cca/seed.json`,存在即整体替换内置默认(不会被脚本升级冲掉)。
- **跳过**:`CC_SEED=0 cca`。**强制重播**:`CC_SEED=1 cca`(合并式,同样不覆盖已改的键)。

> ⚠️ `bypassPermissions` 会跳过所有工具权限确认(含改/删挂进去的真实项目文件)。
> 在隔离容器里相对安全,但请知悉。不想默认免确认就在自己的 `seed.json` 里改 `defaultMode`。

## 公共 Skill(随镜像分发)

仓库 `assets/skills/` 下的 skill(目录名一律 `cc-` 前缀)会打进镜像,容器**每次启动**自动同步到卷内 `~/.claude/skills/`(个人级,所有项目可用):

- **自带**:`cc-commit` —— 说"提交一下"时按团队约定式提交(Conventional Commits)规范生成 commit message 并提交。想加更多公共 skill,照 `cc-` 前缀在 `assets/skills/` 下建目录即可。
- **更新**:改仓库 → CI 构建 → `cca update` → 下次 `cca` 生效;老机器老卷零操作。
- **清理**:镜像里删掉的公共 skill,卷里同步删除,不残留。
- **隔离**:非 `cc-*` 的自建 skill 永不触碰,放心往卷里加自己的。

约定细节见 [`assets/skills/README.md`](assets/skills/README.md)。

## 公共 statusLine(随镜像分发)

仓库 `assets/statusline.sh` 会打进镜像,容器**每次启动**自动同步到卷内 `~/.claude/statusline.sh`,并把 `statusLine` 块合并进 `settings.json`(默认配置:`model · cwd (branch [!N ?N]) · pct%`,按用量变色的上下文百分比 + starship 风格 git 状态)。

- **更新**:改仓库 → CI 构建 → `cca update` → 下次 `cca` 生效。
- **自定义**:**改 `settings.json` 里 `statusLine.command` 指到自己的脚本**(比如 `~/.claude/my-statusline.sh`),不要直接改 `~/.claude/statusline.sh` —— 下次镜像同步会被覆盖(等同公共 skill 约定)。
- **跳过默认**:删 `settings.json` 里的 `statusLine` 块即可恢复 Claude Code 原生(空)行为。

## 第三方中转(profile)

每家中转商写一个 profile 文件放在 `~/.config/cca/<名>.env`,想用哪家就 `CC_PROFILE=<名> cca`。
官方订阅是内置的空 profile(`official`),无需建文件 —— 不带 `CC_PROFILE` 就是它。

**建一个 profile**:`cca init <名>` 从仓库 `profiles/` 模板一键生成(现有 **minimax**、**glm** 两份):

```bash
cca init glm                 # 生成 ~/.config/cca/glm.env(自动 chmod 600),再编辑填 KEY
CC_KEY=你的KEY cca init glm   # 或一步到位:生成的同时把 KEY 注入
```

模板之外的中转商,手建 `~/.config/cca/<名>.env` 即可(键见下表)。

**用**:
```bash
CC_PROFILE=minimax cca    # CC_PROFILE 写错或不存在时,cca 会列出所有可用 profile
```

**profile 里的键**:
| 键 | 说明 |
|------|------|
| `ANTHROPIC_BASE_URL` | 中转 / 自建网关的 base url |
| `ANTHROPIC_AUTH_TOKEN` | 令牌(走 Bearer);若中转用 x-api-key 则改用 `ANTHROPIC_API_KEY` |
| `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` | 各档默认模型名(中转模型名可能与官方不同) |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | 触发自动压缩(auto-compact)的上下文窗口大小,配合大窗口模型(如 1M)调大;不确定就沿用模板值、别动 |
| `HTTP_PROXY` / `HTTPS_PROXY` | 运行时代理(每家的属性:境外要、国内不要);容器内用 `host.docker.internal` |

> ⚠️ profile 含真实 API KEY,只存在各机 `~/.config/cca/`,不入库(仓库里只有占位符模板)。
> 跨机下发建议用配置管理工具的 secret 机制,而非明文复制。

## 平台支持

| 平台 | 说明 |
|------|------|
| **macOS** | 原生支持(Docker Desktop / OrbStack) |
| **Linux** | 原生支持;`cca` 已内置 `--add-host host.docker.internal:host-gateway`,宿主机代理开箱可用 |
| **Windows + WSL2** | 在 WSL2 发行版里跑,`cca` / 代理 / 挂载原样可用;项目建议放 WSL 文件系统内(别放 `/mnt/c/...`,跨文件系统 bind mount 性能差) |

## 持久化说明

- **配置/登录态/历史**:按 profile 各存一个命名卷(官方订阅 → `claude-config`,中转 → `claude-config-<名>`),挂到容器 `/home/node/.claude`,容器重建不丢;几家可同时开、互不干扰。
  官方订阅的 OAuth 登录态也在这里,首次登录后不用再登。
  清空某个 profile(会退出登录 + 重新播种):`docker volume rm claude-config`(官方)/ `docker volume rm claude-config-<名>`(中转)
- **会话历史按项目隔离**:项目目录以宿主机同名路径挂进容器(Claude 按 cwd 存会话),`claude --continue/--resume` 只看到当前项目的会话,不同项目不串。
  旧版 cca 统一挂 `/workspace`,升级后老会话不再出现在 resume 列表(数据仍在卷内 `projects/-workspace/`,没有丢)。
- **git 身份**:在 `~/.config/cca/common.env` 里配 `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`(及对应 `GIT_COMMITTER_*`),对所有 profile(含官方订阅)生效;profile 里同键可覆盖。不复用宿主机 `~/.gitconfig`。
- **SSH**:默认转发宿主机 ssh-agent(挂的是 agent **socket**,私钥本体不进容器,容器只能请求签名、拿不到钥匙),macOS(OrbStack / Docker Desktop)与 Linux 均零配置,容器内 `git push` SSH 仓库开箱可用。
  前提是宿主机 agent 里有 key:macOS 一次性 `ssh-add --apple-use-keychain`(重启后 `ssh-add --apple-load-keychain`,可写进 `~/.zshrc` 自动恢复);Linux 无桌面环境需自行起 agent。
  `CC_SSH=0` 关闭;特殊环境(如 colima)用 `CC_SSH_SOCK` 显式指定 socket 路径。在意每次使用都确认的,宿主机换带 Touch ID 确认的 agent(Secretive / 1Password)或 `ssh-add -c`,cca 不干预 agent 侧策略。

## 自己构建镜像

镜像基于 Node 24,内置 Python 3 / OpenJDK 17 / 常用数据库客户端与网络排查工具(明细见 `Dockerfile`)。
改了 `Dockerfile` 想本地重建 / 推自己的 registry:

```bash
# 本地构建(单架构,给本机用)。不传 CC_VERSION 会装当天 latest,构建不可复现、
# 也无法按版本回滚;想固定版本就显式传(版本号见 npm view @anthropic-ai/claude-code version):
docker build --build-arg CC_VERSION=1.2.3 \
  -t your-registry.example.com/namespace/claude-code:latest .
docker push your-registry.example.com/namespace/claude-code:latest
```

多架构(amd64 + arm64)镜像由 CI 自动构建 —— fork 后在仓库配好这几个 Secret;push 到 `main` / Actions 页手动 / 每日定时均可触发,始终装 npm 上最新版 claude-code。镜像同时打三个 tag:`latest`、claude-code 版本号(新版有问题时把 `CC_IMAGE` 指到旧版本号即可回滚)、git sha;定时构建在没有新版时自动跳过,不做重复构建:

| Secret | 说明 |
|------|------|
| `ACR_REGISTRY` | 镜像仓库地址(如 `registry.example.com`) |
| `ACR_IMAGE_NAME` | 命名空间/镜像名(如 `namespace/claude-code`) |
| `ALIYUN_USERNAME` / `ALIYUN_PASSWORD` | registry 登录凭证 |

## 排错

遇到问题先跑 **`cca doctor`** —— 一次性自检 docker / `CC_IMAGE` / 当前 profile / ssh-agent / 卷与版本,把下表大半的项自动查一遍,直接给 ✅/⚠️ 清单和处理提示。仍未解决再对照下表:

| 现象 | 排查方向 |
|------|----------|
| 提示未检测到 docker / daemon 没在跑 | 装并**启动** Docker Desktop / OrbStack;`docker version` 能出版本号才算就绪 |
| 启动即报鉴权/401 | (中转)`ANTHROPIC_BASE_URL`、令牌是否正确;Bearer 与 x-api-key 是否选对变量 |
| 连接超时 / 需走代理 | profile 里设 `HTTP_PROXY` / `HTTPS_PROXY`(容器内不能用 127.0.0.1,用 `host.docker.internal`) |
| 模型不存在/报错 | 中转模型名与官方不同,在 profile 里改 `ANTHROPIC_DEFAULT_*_MODEL` |
| 提交报 "empty ident" | 在 `~/.config/cca/common.env` 里配 `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`(及 `GIT_COMMITTER_*`) |
| 容器内 `git push` SSH 仓库失败 | 宿主机 `ssh-add -l` 是否列出 key(macOS 重启后需 `ssh-add --apple-load-keychain`;Linux 无桌面需自行起 agent);不想用 SSH 就 `CC_SSH=0` + HTTPS remote + token |

## 卸载

cca 落地的东西分三处,按需清理:

```bash
rm -f ~/.local/bin/cca                       # 1. 脚本本体
rm -rf ~/.config/cca                          # 2. 所有 profile / common.env / seed.json(含真实 KEY,删前确认)
docker volume ls -q | grep '^claude-config'   # 3. 登录态/历史卷:先看有哪些
docker volume rm claude-config claude-config-<名>   #    再逐个删(会退出登录、清空历史)
docker rmi "$CC_IMAGE"                         # 4. 镜像(可选,占空间)
```

> 只想重置某个 profile(退出登录 + 重播默认配置)而不卸载,删对应的卷即可,见「持久化说明」。
