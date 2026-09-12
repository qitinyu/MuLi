# Pilihos 项目协作约定

## 更新日志（必须遵守）
- 每次代码更新（新功能、修复、重构）完成后，必须把本次改动写入仓库根目录的《Pilihos更新日志.md》。
- 版本号从 `1.0.7.0` 起，与 `AppScope/app.json5` 的 `versionName` 保持一致；子版本按迭代批次递增（如 1.0.7.1）。
- 格式参考日志中 `### Pilihos V1.0.6` 段落：
  - 顶部用 `### Pilihos V1.0.x` 作段标题；
  - **倒序书写：新内容写在段落最前面**（同一版本内，最新的迭代批次在最上方）；
  - 按 `> 分类`（如 > 主页、> 视频区、> 设置）分组；
  - 每项一行 `- [✅] 描述`，语言与现有日志一致（中文），可附 issue 号。
- 先改代码、后补日志，日志描述以实际落地行为准，不确定的内容不写。

## 构建备注
- 命令行构建：`hvigorw.bat assembleHap --mode module -p product=default`，需要环境变量 `DEVECO_SDK_HOME="D:/DevEco Studio/sdk"` 与 `NODE_HOME="D:/DevEco Studio/tools/node"`。
- 本机 CLI 打包在 `@PackageHap` 阶段可能因 Java 打包工具崩溃（exit 3221226505）失败；`CompileArkTS` 通过即代表代码无误，出包以 DevEco Studio 为准。
