# 上游署名与许可证

基于 [PiaoyangGuohai1/GoldPrice（JDGold）](https://github.com/PiaoyangGuohai1/GoldPrice) 二次开发，保留作者 PiaoyangGuohai1 署名。上游项目声明使用 MIT License。

本次上传的阶段二 ZIP 没有原 LICENSE，阶段三也没有生成冒充原件的许可证。没有改动或删除用户已有应用外壳中的原许可证和资源。

## 本仓库 LICENSE 的来源

核查上游仓库（默认分支 main，2026-11-06）：根目录只有 `.gitignore`、`Info.plist`、`JDGold.app`、`Package.swift`、`README.md`、`Resources`、`Sources`、`build.sh`，**没有 LICENSE 文件**；仅在 README 的 License 段落声明「MIT License」，GitHub API 的 license 字段也为空。上游仓库创建于 2026-02-03，同日首次提交。

因此本仓库根目录的 `LICENSE` 是**依据上游 MIT 声明整理的标准 MIT 正文**，版权行为 `Copyright (c) 2026 PiaoyangGuohai1`（年份取自上游仓库创建年份）；它**不是上游原文件，也不是上游作者提供的原件**。此前「将原 LICENSE 逐字复制」的要求因上游未提供该文件而无法执行，此处如实记录，不冒充原件。日后若取得上游原件，应以原件替换本文件。

`build.sh` 发现根目录 LICENSE 后会原样复制到应用资源目录；复用旧外壳时保留其中已有许可证。请注意：把 LICENSE 放在仓库根目录，意味着本仓库（含二次开发新增代码）在 GitHub 上会被识别为 MIT 授权；如需为新增部分单独约定条款，请仓库所有者另行补充。

阶段三新增：菜单栏/菜单设计、NSPanel 毛玻璃悬浮窗、SwiftUI 偏好与规则编辑、系统通知与 Bark 引导、来源时间解析和交互测试。功能来源详见 README。阶段二预警引擎与存储源码保持原样。

阶段四新增：公开在岸 USD/CNY 汇率、国内溢价、今日本地分钟采样、手绘走势与采集高低、对应边界测试。没有变更原行情 Provider 或预警引擎/存储。
