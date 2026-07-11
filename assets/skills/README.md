# 公共 Skill(随镜像分发)

此目录下的 skill 会被 COPY 进镜像 `/opt/cc-assets/skills`,每次容器启动时由
entrypoint(`assets/cc-entrypoint`)同步到卷内 `~/.claude/skills/`(个人级,所有项目可用)。

约定:

- **目录名必须以 `cc-` 为前缀**(如本仓库自带的 `cc-commit/SKILL.md`)。
  同步逻辑靠该前缀识别公共 skill:启动时先删卷内 `cc-*` 再铺当前版,
  镜像里删掉的 skill 不会在卷里残留;非 `cc-*` 的用户私有 skill 永不触碰。
- **不要放密钥**。带密钥的配置走 profile env-file(`~/.config/cca/<名>.env`)。

更新路径:改这里 → CI 构建 → `docker pull` → 下次 cca 启动自动生效,老机器老卷无需任何手动操作。
