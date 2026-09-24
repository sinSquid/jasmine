# 功能状态

本文件是功能状态的唯一事实来源，基线为 `e514be163ec39a6f9e0d2799580d132324e23470`（2026-09-24）；`[x]` 仅表示实现和相关测试均完成，`[ ]` 可能表示待实现或已有实现但待验证，具体以条目文字为准。

本次仅进行静态阅读，未运行应用和测试；历史 README 中的勾选不作为测试通过证据，已有功能在补齐验证前保持未勾选，并不表示实现已移除。

## 已有实现，待验证

- [ ] 分类浏览、排序与分页已有界面和通道实现，待补充相关测试（[入口](lib/screens/browser_screen.dart)）。
- [ ] 漫画搜索及搜索历史已有实现，待验证空结果、分页和异常路径（[入口](lib/screens/comic_search_screen.dart)）。
- [ ] 漫画详情、章节与在线阅读已有实现，待验证翻页、缩放、预加载和阅读进度（[入口](lib/screens/comic_reader_screen.dart)）。
- [ ] 收藏及收藏文件夹管理已有界面和通道实现，待验证变更与失败路径（[入口](lib/screens/favorites_screen.dart)）。
- [ ] 浏览历史与继续阅读已有实现，待验证进度恢复及清理行为（[入口](lib/screens/view_log_screen.dart)）。
- [ ] 漫画下载管理与下载内容阅读已有实现，待验证并发、重试与离线可用性（[入口](lib/screens/downloads_screen.dart)）。
- [ ] 漫画导入及多格式导出已有实现，待验证权限、格式兼容和中断行为（[通道](lib/basic/methods.dart)）。
- [ ] 评论列表、发布及回复已有界面和通道实现，待验证分页与失败处理（[入口](lib/screens/comments_screen.dart)）。
- [ ] 账号登录、预登录、退出和外部注册入口已有实现，待验证真实流程与异常路径（[入口](lib/screens/first_login_screen.dart)）。
- [ ] WebDAV 合并、覆盖上传、覆盖下载及自动同步已有入口，待验证冲突、超时与数据安全（[入口](lib/basic/web_dav_sync.dart)）。
- [ ] API/CDN 切换与代理配置已有实现，待验证网络异常和配置恢复（[入口](lib/screens/network_setting_screen.dart)）。
- [ ] 主题、字体、阅读器、缓存等设置已有实现，待验证初始化和持久化（[入口](lib/configs/configs.dart)）。
- [ ] Android 刷新率、音量键以及桌面窗口与键盘交互已有实现，待完成对应平台验证（[说明](docs/仓库分析.md)）。
- [ ] 访问验证与 Pro 状态相关入口已有实现，待授权范围内的功能和安全验证（[说明](docs/仓库分析.md)）。
- [ ] 版本检测和升级提示已有实现，待验证版本资源与异常处理（[入口](lib/configs/versions.dart)）。
- [ ] Android、iOS、macOS、Windows、Linux 和 OpenHarmony 平台工程已存在，待补齐各平台构建与冒烟证据（[验证说明](docs/开发与验证.md)）。

## 待实现或待完善

- [ ] 游戏功能仅发现通道与模型且未确认完整页面和测试，保持待完成状态（[通道](lib/basic/methods.dart)）。
- [ ] 对齐 SDK、依赖和原生核心版本并建立可复现构建基线（[现状](docs/开发与验证.md)）。
- [ ] 建立覆盖真实业务及失败边界的一键自动化测试套件（[计划](docs/开发与验证.md)）。
- [ ] 接入格式、静态分析、Rust Clippy、Release 全量测试和生产构建门禁（[现状](docs/仓库分析.md)）。
- [ ] 实现符合团队要求的 Tag 发布及不可覆盖制品流程（[现状](docs/开发与验证.md)）。
- [ ] 消除 OpenHarmony 通道参数日志的敏感信息风险并补充验证（[依据](docs/仓库分析.md)）。
- [ ] 明确原生调用、图片预加载和下载任务的资源硬上限与退化行为并完成性能验收（[依据](docs/仓库分析.md)）。
