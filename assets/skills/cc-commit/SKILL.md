---
name: cc-commit
description: 当用户要求提交代码、创建 git commit、或说"提交/commit 一下"时使用。按团队的约定式提交(Conventional Commits)规范生成 commit message 并提交。
---

# cc-commit —— 团队提交规范

本团队采用 **Conventional Commits 1.0.0**。提交前先看清改动(`git status` / `git diff`),再按下面的规范写信息并提交。

## 格式

```
<type>(<scope>): <主题>

<正文,可选>

<页脚,可选>
```

- **type**:必填,见下表。
- **scope**:可选,受影响的模块/包/目录,如 `(auth)`、`(api)`、`(deps)`;跨多模块可省略。
- **主题**:必填,一句话祈使句说清"做了什么",中文,首字母不大写、结尾不加句号,≤ 50 字。
- **正文**:解释**为什么**改、与之前行为的差异,而非罗列文件名;与主题空一行,每行 ≤ 72 字。
- **页脚**:关联 issue、破坏性变更等,见下。

## type 清单

| type | 用途 |
|------|------|
| `feat` | 新增功能(对应语义化版本 MINOR) |
| `fix` | 修复缺陷(对应 PATCH) |
| `docs` | 仅文档改动 |
| `style` | 不影响逻辑的格式(空格、分号、格式化) |
| `refactor` | 重构:既非新功能也非修 bug |
| `perf` | 性能优化 |
| `test` | 新增或修改测试 |
| `build` | 构建系统或依赖变更(如 npm、Docker、Makefile) |
| `ci` | CI 配置与脚本(如 GitHub Actions) |
| `chore` | 杂项:不改 src/test 的其他维护性改动 |
| `revert` | 回滚某次提交(正文写 `Reverts <hash>`) |

## 破坏性变更

两种标注方式,择一或并用:

- type/scope 后加 `!`:`feat(api)!: 移除 v1 端点`
- 页脚加 `BREAKING CHANGE: <说明>`(会触发语义化版本 MAJOR)

## 关联 issue(页脚)

- 自动关闭:`Closes #123`(多个:`Closes #123, #124`)
- 仅引用不关闭:`Refs #123`

## 示例

```
feat(auth): 支持邮箱验证码登录

原短信通道成本高,新增邮箱验证码作为备选登录方式。
验证码 5 分钟有效,复用现有限流中间件。

Closes #142
```

```
fix(api)!: 分页参数从 1 起始改为 0 起始

BREAKING CHANGE: page 参数语义变更,调用方需 -1 适配。
```

## 流程与边界

1. 看清 `git diff` 与用户意图一致;有可疑的无关改动先问,不闷头提交。
2. 一次提交只做一件事;改动跨多个不相关主题时,**建议拆成多个 commit**,而非塞进一条。
3. `git add` 相关文件后 `git commit`。**不加 `Co-authored-by` 尾注。**
4. **只写信息 + 提交,不 push**(推送可能触发 CI / 发布,交给用户决定)。
5. 工作区有冲突标记、未解决的合并、或明显未完成的半成品时,先提示用户,不直接提交。
