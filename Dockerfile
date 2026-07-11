FROM node:24-bookworm-slim

# 系统工具,按用途分行(client = 连接远程/其他容器的服务,非本机起服务):
#   基础 & Claude 依赖: git ripgrep curl ca-certificates less jq tzdata openssh-client
#   语言运行时:         python3(+pip/venv,python-is-python3 让 python 指向 python3) default-jdk-headless(OpenJDK 17;Node 24 已由基础镜像提供)
#   数据库客户端:       default-mysql-client(mysql) redis-tools(redis-cli) postgresql-client(psql)
#   网络排查:           iputils-ping dnsutils(dig/nslookup) netcat-openbsd
#   编辑 & 下载解压:    vim unzip wget
#   交互体验:           bash-completion(git 等 Tab 补全;别名见下方独立 RUN)
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ripgrep curl ca-certificates less jq tzdata openssh-client \
      python3 python3-pip python3-venv python-is-python3 \
      default-jdk-headless \
      default-mysql-client redis-tools postgresql-client \
      iputils-ping dnsutils netcat-openbsd \
      vim unzip wget \
      bash-completion \
    && rm -rf /var/lib/apt/lists/*

# 全局安装 Claude Code CLI。CC_VERSION 由 CI 传入 npm 上的最新版本号:
# 版本变了才让本层缓存失效(上面较重的 apt 层缓存始终保留),
# 版本号同时用作镜像 tag,新版出问题可按版本回滚。本地构建不传 = latest。
ARG CC_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CC_VERSION}" \
    && npm cache clean --force

# git 安全目录(容器内 node 操作宿主挂载目录时避免 dubious ownership 报错)
# + Claude 配置目录(cca 以命名卷挂载 /home/node/.claude,此路径是与 cca 的契约)
RUN git config --system --add safe.directory '*' \
    && install -d -o node -g node /home/node/.claude

# 常用别名(只影响 `cca bash` 交互调试;Claude 的 Bash 工具是非交互 shell,不读 .bashrc)
RUN cat >> /home/node/.bashrc <<'EOF'

# --- cca 常用别名 ---
alias ll='ls -alFh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph -20'
EOF

# 公共 Skill(cc- 前缀,约定见 assets/skills/README.md)随镜像分发;
# 入口脚本每次启动把它们同步进卷的 ~/.claude/skills,再按原规则拉起 claude
# (首参为空或以 - 开头 ⇒ 交给 claude,否则按命令执行,如 `cca bash` 调试)。
COPY --chown=node:node assets/skills /opt/cc-assets/skills
# cca 本体也随镜像分发:`cca update` 拉完镜像后从这里提取自升级,
# 脚本与镜像走同一条 registry 通道,版本天然配对(不依赖 GitHub raw 可达性)
COPY --chmod=755 cca /opt/cc-assets/cca
COPY --chmod=755 assets/statusline.sh /opt/cc-assets/statusline.sh
COPY --chmod=755 assets/cc-entrypoint /usr/local/bin/cc-entrypoint

USER node
# 兜底工作目录(cca 运行时用 -w 覆盖为宿主机真实路径,让会话历史按项目隔离)
WORKDIR /workspace

# 容器/CI 场景:总开关,连带禁用自动更新 + 遥测 + 错误上报等非必要流量
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# 中性 locale/时区 + 本机地址代理豁免的默认值;运行时可被 --env-file / -e 覆盖
ENV LANG=C.UTF-8 \
    TZ=UTC \
    NO_PROXY=localhost,127.0.0.1,host.docker.internal

ENTRYPOINT ["/usr/local/bin/cc-entrypoint"]
CMD ["claude"]
