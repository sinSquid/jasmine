# Jasmine 项目执行入口

## 阅读顺序与规范来源

开始工作前阅读本文件、[团队项目规范](docs/standards/团队与AI%20Coding项目规范.md)、[人员执行规范](docs/standards/团队成员研发执行规范.md)和[通用项目工作流程](docs/standards/项目工作流程.md)，再阅读 [feature.md](feature.md)、[仓库分析](docs/仓库分析.md)和[开发与验证](docs/开发与验证.md)。

`docs/standards/` 为 2026-09-24 从 `/Users/sin/code/agents`、`/Users/sin/code/doc` 引入的原文快照；通用规则在上述文档维护，本文件只补充 Jasmine 的执行细节，更新快照时同时检查两份团队规范的一致性。

## 项目边界

- 本仓库包含 Flutter 客户端和 Android、iOS、macOS、Windows、Linux、OpenHarmony 原生桥接，业务核心由 CI 从 `niuhuan/jasmine-rs-core` 获取到 `native/`，不得将未读取的核心实现视为已审查。
- Flutter 基线以 `.fvmrc` 和目标工作流为依据；`pubspec.yaml`、构建与发布工作流的 SDK 约束和工具链存在待核验差异，修改版本前须完成方案确认。
- `lib/basic/methods.dart` 的通道名、方法名、JSON 参数和返回封装，以及原生 ABI 是跨仓库兼容边界；调整时必须同时核对核心版本和所有受影响平台。
- `feature.md` 是唯一功能状态事实来源；`README.md` 和 `README-zh.md` 的原有内容必须保留，仅允许新增说明和文档入口，原有功能列表作为历史介绍保留，当前验收状态以 `feature.md` 为准；实现存在但未完成相关测试的条目保持未勾选并说明状态。

## 构建与检查

环境准备、原生库路径和各平台命令见[开发与验证](docs/开发与验证.md)，以下命令均在仓库根目录执行，前提是依赖、SDK 和所需原生核心已就绪：

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --timeout 60s
```

生产构建必须覆盖受影响平台，例如 Android 使用 `flutter build apk --release --target-platform android-arm64`，macOS 使用 `flutter build macos --release`；其他平台见验证文档，不能用单个平台通过替代全部受影响平台验证。

Rust 格式、Clippy、Release 全量测试和 Release 生产构建门禁按通用工作流程执行；必须先取得核心源码、读取其规范并确认实际 Cargo workspace、feature 和 target，再执行对应命令，禁止在缺少核心源码时声称通过或豁免。

当前 CI 只有手动工作流，尚不满足完整门禁；本文件列出的目标检查不代表已接入或已通过，失败或缺失检查必须如实记录并阻止相应受控操作。

## Git 与发布具体约束

- 当前远端为 `origin`，默认主分支为 `master`；改动通过功能或修复分支发起 MR（GitHub 上为 PR），不得直接推送主分支。
- 提交前核对 `git var GIT_AUTHOR_IDENT`；必须具有已确认的仓库级姓名和 `@xunlei.com` 邮箱，否则按通用工作流程询问并配置本仓库身份，SSH 公钥注释邮箱不等于提交身份。
- 提交、推送、Tag 和发布分别遵守人员授权规则；只有当前请求明确要求推送才可推送，推送前同步目标分支、检查最终差异并满足全部验证门禁。
- Tag 只能指向以仅快进方式同步后、干净且与 `origin/master` 完全一致的 `master` 提交，名称和目标提交由用户明确授权。
- 现有 Release 工作流手动创建 Release 并允许覆盖资产，与团队 Tag 制品规则有差距；完成流程对齐前不得沿用其逻辑发布或覆盖制品。

## 架构、性能与安全约束

- Flutter UI 状态、配置状态与原生核心状态必须明确归属，异步回调须处理页面销毁、失败和资源释放。
- 图片解码、预加载、下载并发、缓存和导入导出属于资源敏感路径，应限制单轮工作量、内存、线程和队列容量；界面可选下载线程数为 1–5 不能证明核心具有硬上限。
- 修改原生并发或 Rust 数据处理路径时应用通用数据面约束，并验证吞吐、CPU、内存、队列、失败率和尾延迟，禁止 UI 线程阻塞、无界创建线程或随数据量增长的无界扫描。
- 通道参数可能包含账号、密码和 WebDAV 凭据，禁止完整输出参数或将真实数据写入测试和报告；涉及认证、权限、用户数据与同步覆盖操作时遵守团队专项门禁。
- 原生库、生成头文件、版本资源和平台 SDK 必须与目标构建匹配；禁止提交密钥、签名材料及本地生成制品。

## 停止条件

需求或规范存在实质冲突、方案未经确认、核心源码或构建依赖缺失、提交身份不合规、检查失败、版本与制品无法对应时，停止对应实现或受控操作并报告证据；仍可继续授权范围内的只读分析和规划文档整理。
