# board-superpowers

> **一个让多 AI 并行执行像真团队、而不像混乱的强制层。**
>
> 以 plugin 形态构建，同时支持 **Claude Code** 和 **OpenAI Codex CLI**。
> 组合调用 [`superpowers`](https://github.com/anthropics/claude-plugins-official)（TDD、code review、debugging）和 [`gstack`](https://github.com/garrytan/gstack)（design、QA、security）——而不是替代它们。

[English](./README.md) · **简体中文**

---

## 为什么存在

AI 时代架构师的核心价值，**已经不是写代码**。是定义问题、排序方向、设计架构、判断权衡，并且核验 AI 产出的东西到底能不能用。写代码本身正在变成 AI 的活儿。

board-superpowers 把这次角色转移落地成可执行的工作方式。具体说：

- 你同时跑 **N 个并行 Consumer 会话**，对应 **一个 Manager 会话**。
- 你走开。
- 你回来时面对的是 **一队等你 merge 的 PR**，每个都附带一份明确的 `## Human Verification TODO` 清单。
- **核验那份清单是你剩下的工作**——而这个 plugin 的整套形态，都是为了让你这份稀缺注意力撑得更远而设计的。

如果你已经下定决心把精力投到判断和架构、而不是逐行写代码上；并且你愿意把实现工作派给 AI 而不必时刻盯着——这个 plugin 就是给你的。

## 装上之后哪里不一样

| 不用 board-superpowers | 用 board-superpowers |
|---|---|
| 一个终端，盯着一个会话，频繁 rebase | N 个终端，每个挂着一个 Consumer，大部分你根本不看 |
| "我下一步做什么"在你脑子里 | 一个 Manager 会话读板子，告诉你 |
| Sprint 计划是一次有损会话 | Decomposition 是一个 skill，强制 INVEST 和纵向切片 |
| 范围蔓延要在 PR 里才发现 | 范围在 Consumer 认领前就被冻结进 card 正文 |
| Merge 是惊喜 | 每个 PR 都附带结构化的 `## Human Verification TODO` |
| 协调状态在你脑子里 | 协调状态在你**自己的** GitHub Project 里——我们永远不持有 |

## 三根支柱

board-superpowers 站在三个承诺的交点。绝大部分相邻工具只满足其中一两个；同时满足全部三个，才是差异所在。

### 1. 基底承诺——你的板子，永远不归我们

真理只活在**你既有的板子**上（v1 是 GitHub Project；未来通过 `BoardAdapter` 契约接 Linear、Jira 等）。我们永远不持有托管控制平面，不跑后端，不让你登录我们的服务。

如果哪天某个 feature 需要把持久化状态放到"你的板子 + 你的 git remote"以外的地方，这个承诺就破了。这是结构性的，不是嘴上说说——这正是我们和 Devin / Factory / 其他托管型产品的根本分野，他们的商业模式**必须**让自己拥有这套状态。

### 2. 方法论以代码形式嵌入

敏捷纪律是被 plugin **强制**的，不是你去配的：

- 每张 card 都满足 **INVEST**——Independent / Negotiable / Valuable / Estimable / Small / Testable。
- 永远 **纵向切片** 优先于 layer 切分。
- **拉式工作**：Consumer 原子认领，Manager 不负责派活。
- **一会话一 PR**，不存在多 card 共会话。
- **轻量化 retro**——从 PR 笔记里聚合，不是另开一个仪式。
- **软 WIP 上限**（默认 5）——告警，但不阻塞。
- card 尺寸只有 **XS / S / M / L**——没有 story point，没有 velocity，没有针对个人的 KPI。

任何带有 sprint-cadence-cosplay 味道的东西（story point 估点、velocity 跟踪、retro-as-meeting）都被刻意去掉了。AI 编排把"什么资源稀缺"这个问题翻转过来，人类团队所需要的大多数仪式在这里都是噪声。

### 3. Composition 是永久的

board-superpowers **永远不重新实现 TDD、QA、code review、brainstorming、security audit**。这些归 `superpowers` 和 `gstack`。board-superpowers 是把它们组合成 routine 的**调度层**：

- Manager 的 intake routine 路由到 `gstack:/office-hours` 和 `superpowers:brainstorming`。
- Consumer 的 implementation routine 委托给 `superpowers:subagent-driven-development`。
- Consumer 的 PR 提交前的 verification chain 依次调用 `superpowers:verification-before-completion` → `superpowers:requesting-code-review` → `gstack:/review` → `gstack:/codex`（跨平台对抗式 review）→ `gstack:/qa`（UI 类 card）→ `gstack:/cso`（被标记为安全风险的 card）。

如果上游 plugin 已经有的纪律我们就用；如果哪天我们 ship 了一个重复的，那是 bug。

## 两种角色

每个会话相对于 kanban 都恰好扮演一种角色。路由根据你的第一句话自动完成。

### Producer——保持板子健康的会话

> v1 唯一的 Producer 类角色：**Manager**。

Manager 会话**长生命周期、聚合视图、永远不写代码**。它在五个簇里暴露 15 个能力：

- **读取原语**——atomic kanban query、按优先级排序的待审 PR 队列、阻塞会话识别、当日派发推荐、板子健康快照、切换回某 card / Thread 时的上下文回放。
- **动作 features**——隔夜批量派发（"人休息，agent 不休息"）、interactive intake & 设计路由、INVEST 兼容的 decomposition、带 5 步补救阶梯的 triage。
- **节奏 features**——延迟式过期会话识别、事件驱动的 retro routine（不绑定 sprint cadence）、每周聚合报告。
- **项目级会话型 features**——质量 harness 设置会话（把你项目的"金科玉律"编成 lint + 结构化测试 + 自动 PR）、kanban 自身的清理与维护。

### Consumer——把单卡做到完成的会话

> v1 唯一的 Consumer 类角色：**Implementer**。

Consumer 会话**原子认领一张 Ready card**，拉到它的 spec，通过 skill 委托执行实现工作，跑对抗式自检 review，开 PR，处理 review 周期，干净地终止。

两种运行模式：

- **Mode-1**（架构师人工启动）：你在一个新终端里粘贴一个 kick-off prompt——Claude Code 和 Codex CLI **都支持**。
- **Mode-2**（Producer 启动）：Manager 把 Consumer 当 subagent 启动——v1 **仅 Claude Code**。

每个 Consumer 跑在自己专属的 git worktree 里。N 个并行 Consumer 因此永远不会共享 HEAD。

## 快速上手

### 前置依赖

board-superpowers 在依赖缺失时会拒绝运行——这是有意设计：

```bash
# superpowers — TDD、subagent-driven-development、code review
/plugin install superpowers@claude-plugins-official

# gstack — design、QA、视觉 review、security
cd ~/.claude/skills && git clone https://github.com/garrytan/gstack && cd gstack && ./setup
```

此外还需要：`gh` CLI（已登录、带 `project` scope）、`git`、`python3`。

### 安装 board-superpowers

```bash
git clone https://github.com/PanQiWei/board-superpowers ~/.claude/plugins/board-superpowers
```

#### Claude Code

```
/plugin add local ~/.claude/plugins/board-superpowers
```

CC 在 plugin 加载时自动发现 `hooks/hooks.json`，无需额外步骤。

#### Codex CLI

Codex CLI 不会自动发现 plugin 自带的 hook（plugin manifest 规范没有 `hooks` 字段）。安装完后运行一次 SessionStart hook 注册：

```bash
# 推荐先打印 snippet 看一下：
bash ~/.claude/plugins/board-superpowers/scripts/register-codex-hooks.sh

# 然后自动 merge 到用户级 ~/.codex/hooks.json：
bash ~/.claude/plugins/board-superpowers/scripts/register-codex-hooks.sh --install-user

# 或者写到当前 repo 的 ./.codex/hooks.json（需要 repo trust）：
bash ~/.claude/plugins/board-superpowers/scripts/register-codex-hooks.sh --install-repo
```

脚本是幂等的——重复运行会替换已存在的 entry 而不是重复添加；覆盖前会先备份 `hooks.json`。卸载用 `--uninstall-user`。

### 每个 repo 的一次性引导

每一个你想启用 board-superpowers 的 repo——目前是手动流程，自动化 bootstrap skill 会在未来版本提供。

1. **在 GitHub UI** 创建一个 Project v2，在它里面建一个 `Status` 单选字段，选项必须严格按这个顺序：`Backlog → Ready → In Progress → Blocked → In Review → Done`。
2. **添加标准标签**：
   ```bash
   bash ~/.claude/plugins/board-superpowers/scripts/setup-labels.sh
   ```
   会创建 `wip-override` / `suspended` / `security` / `pr-contract-override`（幂等——已存在的会跳过）。
3. **在 repo 根目录创建 `.board-superpowers/config.yml` 并提交**：
   ```yaml
   project: <owner>/<number>      # 例如 PanQiWei/4
   ```
   再创建 `.board-superpowers/config.local.yml`（不提交，per-user）：
   ```yaml
   wip_limit: 5                   # 个人并行 capacity；soft cap，默认 5
   ```
4. **验证**：
   ```bash
   bash ~/.claude/plugins/board-superpowers/scripts/check-deps.sh
   bash ~/.claude/plugins/board-superpowers/scripts/read-board.sh \
     --owner <owner> --project <number> --status Ready
   ```
   两个命令都应该 exit 0；第二个会打印 Ready 卡的 JSON 列表（空 `[]` 也正常）。
5. **可选——在 `CLAUDE.md` 和 `AGENTS.md` 加路由块**，让 agent 明确知道要 invoke 本 plugin 的 skills。entry skill (`using-board-superpowers`) 不加路由块也能在常见短语上触发，但显式路由提高可靠性。可参考 `~/.claude/plugins/board-superpowers/AGENTS.md` § "board-superpowers session routing" 复制粘贴。

到此结束。完成 step 5（或跳过 step 5 直接结束 step 4）后，在你的 repo 里开一个全新的 CC session，输入 "what should I work on" 验证 entry skill 触发即可。

## 典型一天

```
┌─────────────────────────────────────────────────────────────┐
│  早上                                                       │
│  打开 Manager 会话："what should I work on?"               │
│                                                             │
│  Manager 完成 preflight 并报告：                            │
│    - 2 个 PR 等你核验                                       │
│    - 3 张 card 在执行中                                     │
│    - 5 张 card Ready 状态可派发                             │
│                                                             │
│  你核验掉 2 个 PR 并 merge。                                │
│  你向 Manager 询问当日的 dispatch 推荐。                    │
│  你打开 3 个新的 Consumer 终端，粘贴 kick-off prompt，      │
│  然后走开。                                                 │
├─────────────────────────────────────────────────────────────┤
│  中午                                                       │
│  Consumer 完成、开 PR。                                     │
│                                                             │
│  Manager："what needs me?"                                  │
│    -> 3 个 PR 按核验面归类、按优先级排序                    │
│                                                             │
│  你核验、merge、派发下一波。                                │
├─────────────────────────────────────────────────────────────┤
│  下班前                                                     │
│  Manager："I'm leaving — kick off X, Y, Z overnight"        │
│    -> Producer 在受控并发下，逐个派发 Consumer 会话，       │
│       你睡觉的时候它们工作。                                │
│       人休息，agent 不休息。                                │
├─────────────────────────────────────────────────────────────┤
│  周度                                                       │
│  Manager："weekly retro"                                    │
│    -> 把过去 7 天的 PR retro 笔记聚合成 flow 信号、         │
│       decomposition 漂移、以及对 CLAUDE.md 修改的提案       │
│       （在 land 之前你需要先批准）。                        │
└─────────────────────────────────────────────────────────────┘
```

### Manager 开箱即用的三句话

| 你说 | Manager 做 |
|---|---|
| `what should I work on?` / `morning briefing` | 日常 routine——板子快照 + 当日 dispatch 推荐 |
| `I have a new requirement: <X>` | Intake——把你引导穿过设计 skill，再到 decomposition |
| `weekly retro` | Retro——把过去 7 天的 PR 笔记聚合成结构化报告 |

还有 8 句记录在 spec 里——见 `docs/architecture/0002-product-features-and-flows/03-producer-surface.md`。

### 派发一个 Consumer

Manager 会递给你一段 kick-off prompt，形如：

```
[board-card:#42] Work on card #42 in project acme/3.

Start by invoking `consuming-card` skill. It will handle the full
lifecycle: claim (atomic) -> implement -> PR -> update board.

Context the architect added on top of the card body:
None — card body is complete.
```

在项目目录下打开一个新终端，粘贴进去，然后走开。Consumer 只在 PR 已经开好（或者撞到了真的需要你介入的 blocker）时才回过头报告你。

## PR 契约

每个 Consumer 提交的 PR 都附带三段结构化内容：

- **`## Automated Verification`**（必须）——跑了哪些 test / lint / 跨平台 review / 安全检查，哪些通过。verification chain 的审计轨迹。
- **`## Human Verification TODO`**（低风险 card 可省略；需要端到端人工核验时必须）——AI 没法自动化的步骤。**这就是你剩下的工作。** 来源：Producer 的 plan + Consumer 实现期间的补充。
- **`## Retro Notes`**（存在可复用经验时必须）——为未来 card 提供的知识沉淀。**不**包含估算 vs 实际、**不**包含 velocity、**不**包含 KPI 指标。

如果某个必须段缺失，Manager 的 Review Queue routine 会就地标记违规。**结构是协议，内容是项目特定的、永远不预设。**

## 我们明确不做的事

下面这些是"承诺不做"的清单。未来形如"能不能加 X"的提案，应该先和这张清单对账。

- **不做后端、数据库、Web UI。** 真理活在你的板子上。
- **不重新实现上游纪律。** TDD 归 `superpowers`；QA / review / brainstorming / security 归 `gstack`。
- **不替代 CI。** 测试在你 CI 跑的地方跑。
- **不做 story points / velocity / 个人维度的绩效指标。** card 只有 XS / S / M / L。Retro 输出的是 flow 信号，不是 KPI。
- **不让 agent 自己 merge PR。** 人 merge，agent 提案。
- **不做托管安装服务 / 账号注册 / 安装向导。** 分发方式今天是 `git clone` + `/plugin add local`，未来是 marketplace 一行命令。永远不会有托管层。
- **不做方法论扩展集市。** 第三方"纪律 plugin"扩展 routine 永久排除——稳定 plugin 契约的版本债太重，鸡生蛋蛋生鸡的生态风险真实存在，都不符合本项目的定位。
- **v1 不做跨团队 / fleet 视图。** 那是明确的 10x 路径（见下面 Vision），不是 v1。

## 为什么没有 sprint，没有 sub-issue，也没有 story point

绝大多数敏捷流程构件都默认了一个固定的实施吞吐量——大致就是人类开发者按天/周计的产出节奏。这条假设成立时，时间盒（sprint）、按人日切割任务（sub-task / sub-issue）、基于规模的估算（story points）才各司其职。

在 AI 编排的软件研发场景下，实施吞吐量提升 10 至 100 倍，**架构师的注意力却没有**。围绕"实施是瓶颈"建起来的那一整层敏捷流程表面就失去了承重作用，悄然变成仪式。

board-superpowers 把这一层概念逐一过了一遍。每一个被移除的构件都用同一把尺子量过：*它做的事，AI cadence 下别的机制是不是已经做得更好？*

### Sprint——已移除

时间盒假设吞吐量恒定：你 commit 一批工作、在边界做 demo。当卡片以小时为单位落地、而不是以天，commit-batch-demo-retro 这个循环就没什么可装进时间盒了。替代方案：

- **持续流（continuous flow）**——卡片好了就 land。
- **逐 PR demo**——每个 PR 都带 Human Verification TODO；架构师亲自验证就完成了 demo。
- **从 PR Notes 里聚合 retro**——这是信号汇集，不是仪式。

### Sub-issue / sub-task——退化为冗余

Sub-issue 在人类节奏的敏捷里承担过六项职能：

1. 把 feature 切到人日级别（拆解）。
2. 跨多人协调工作（协调）。
3. 给利益相关者展示 feature 级进度（可见性）。
4. 把任务级估算汇总到 feature 级（估算累加）。
5. 在 sprint 内排序 sub-task（排序）。
6. 帮人脑导航复杂工作（心智分块）。

到了 AI cadence 软件研发，四项直接消亡：

- **（1）拆解**——被 **INVEST 兄弟切片** 加 `depends-on` 依赖边替代。卡片本身已经压到小时级，下面再没有还有意义的 atomic 单位可切。
- **（2）协调**——被 **原子 claim 原语** 替代。N 个 Consumer 会话在 git push 层抢同一个 ref，谁赢谁拥有这张卡，没有 parent 当协调点的位置。
- **（4）估算累加**——XS/S/M/L 四档加上"绝对量级在小时"后，把任务级数字加起来给 feature 级再无意义。
- **（5）sprint 内排序**——sprint 没了，自然不存在。

剩下两项——**（3）利益相关者可见性** 和 **（6）心智分块**——粒度上移一层。架构师不再"feature vs sub-task"地想问题，转而以 **Thread**（命名工作主线）和 **Milestone**（可交付目标桶）为单位推理。这两个概念本来就在 board-superpowers 的工作层级里。

结论：parent card 下挂 N 张 sub-card 这种结构，能提供的东西 Thread + 兄弟 Card + 依赖边都已经覆盖；代价却是污染协议纯净度。Parent card 不可被 claim、违反"一卡 = 一个 Consumer 会话 = 一个 PR"不变量、还要引入跨 backend 各家不一的 parent 状态推导规则（GitHub / Linear / Jira 各自对"parent 是否随 child 自动更新"的判定都不同）。

我们尊重用户已经在 GitHub / Linear / Jira 上创建过的 native sub-issue——它们以仅供展示的 metadata 形态附在协议层扁平的 Card 上。但不把它们升格为协议语义。

### Story points——已移除

Story points 当年校准的是 sprint 承诺（"两周内团队能干完多少"）。Sprint 没了、卡片在小时级了，校准的标尺也没了。我们用 **XS / S / M / L** 做粗粒度 sizing——粗到下手快，又细到能在卡片*太大、该再切*时报警。

### Burndown chart、stand-up、Epic——也消亡或转生

- **Burndown chart** 可视化的是 sprint 进度；没有 sprint，每日例行直接读 WIP + Done 计数即可。
- **Stand-up** 是人类团队同步；agent 不需要同步，架构师本来就在读 PR。
- **Epic** 被 **Thread**（主题分组）或 **Milestone**（可交付桶）替代——同样的角色、更贴近敏捷正统的命名、没有多 sprint 容器的预设。

### 用一句话讲完

> 如果某个研发概念假设了"实施是瓶颈"，到了 AI-native 研发场景它八成会退化为冗余。**架构师注意力才是新的瓶颈**；我们保留下来的、新建出来的所有东西，都在为这一点优化。

Spec 层级的论证：[`docs/architecture/0001-positioning.md`](./docs/architecture/0001-positioning.md)（premise P1 / P2b / P3）和 [`docs/architecture/adr/0012-kanban-protocol-as-top-contract.md`](./docs/architecture/adr/0012-kanban-protocol-as-top-contract.md)（让 projection 层能容纳 backend 原生 sub-issue 而不把它们升格的 protocol-shape 决策）。

## 你应该知道的两条设计原则

### Meta-methodology，而不是带观点的预设配置

board-superpowers 提供的是 **机制**：你用来 *建立和演化* 自己实践的会话脚手架与维护 routine。它**刻意不 ship 项目特定的预设**：

- 没有默认 lint 规则。Manager 帮你引导出你自己的。
- 没有默认 PR 段落内容。3 段结构是协议，*内容*是你自己的。
- 没有固定的 WIP 数。一个起步默认值存在；Manager 协助你根据观察到的 flow metric 去调。
- 没有默认 retro 模板。Retro 聚合的是 *你的* 信号，不是我们的。

哪天我们 ship 了一个会替你判断"你项目应该长什么样"的预设，这条原则就破了。

### Default + override + accountability

每一条治理维度都是同一个形状：一个合理的 **默认** 自动执行；**override** 是允许的，但要付出明显代价（编辑配置、写明理由、架构师 prompt）；每一次 override 都留下 **可追溯的痕迹**（audit-log 行、PR 描述、card 线程评论）。

Producer 的 autonomy 矩阵有 14 行，把每一种动作映射到三种之一：**A**（自动执行 + 写 audit log）、**R**（提案 + 等待批准）、**N**（永久禁止）。你随时能看清 AI 做了什么、为什么、以及你是否批准过。

## Vision

v1 论点的两个放大器。两个都明确属于 v1 之后；两个都是路线图上的一等公民。

### 自我改进的方法论（per project）

Retro 信号自动调优你项目的 CLAUDE.md decomposition 规则。在某个项目上用 board-superpowers 第二年时，agent 对你 repo 的"风土人情"——哪些子系统总是被低估、哪些区域每个 PR 都需要 a11y 核验、哪些依赖总是带来意外——的理解会比一个新员工 6 个月之后更准确。方法论本身不变，参数自我调优。

### 跨团队标准

多架构师、多板子、fleet 视图。这套方法论会成为 AI 时代工程团队的通用语，正如 Scrum 之于上一个时代——只不过是用代码而不是用仪式来强制。`BoardAdapter` 契约就是让这件事对非 GitHub 团队可达的关键。

### 明确不做

开放式方法论集市（第三方"纪律 plugin"）。稳定 plugin 契约的版本债太重，鸡生蛋蛋生鸡的生态风险真实存在，不符合本项目的定位。

## 状态

v1 设计正在收尾。实现以 dogfood 形式跑在 plugin 自己的 GitHub Project 上——所有非平凡改动都走 Manager-Consumer 流程。

- 架构 spec：`docs/architecture/`（先读 `0001-positioning.md`）
- 产品 features 与 flows：`docs/architecture/0002-product-features-and-flows/`
- 域模型：`docs/architecture/0003-domain-model/`
- 组件架构：`docs/architecture/0004-component-architecture.md`
- 跨组件契约：`docs/architecture/0005-contracts/`
- 决策记录：`docs/architecture/adr/`

## 升级

```bash
cd ~/.claude/plugins/board-superpowers && git pull
```

然后重启 Claude Code，让 plugin 重新加载。

## License

MIT.
