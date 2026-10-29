# bili-sync 自定义构建

本仓库只维护 **自动构建脚本**，不保存应用源码。每天检查一次上游 [amtoaer/bili-sync](https://github.com/amtoaer/bili-sync)，为指定提交编译 ARMv7 GNU 版本并发布。

- 上游仓库：<https://github.com/amtoaer/bili-sync>
- 使用文档：<https://bili-sync.amto.cc/>
- 上游许可证：[MIT](./License)

## 目录结构

```text
.github/workflows/upstream-build.yaml  # 检测 → 编译 → 发布
scripts/check-upstream.sh              # 判断是否需要构建，生成版本标签
scripts/build-armv7.sh                 # 取回固定提交、应用配置、编译打包
scripts/publish-release.sh             # 推送标签、上传附件、发布 Release
Cross.toml                             # 自定义交叉编译配置
```

## 构建流程

```text
每天检查上游
  → 上游正式版 / main 最新提交
  → 逐版本编译：上游源码（固定 SHA）+ 本仓库 Cross.toml
  → 推送标签 → 创建草稿 → 上传附件 → 发布
```

- **源码**取自上游固定提交，编译结果只由该 SHA 决定。
- **构建配置**取自本仓库当前提交（`GITHUB_SHA`），发布说明中会记录。
- 只有 **Release 已发布且附件完整** 才跳过；草稿或缺附件会重新处理，可直接重跑失败的 workflow。

调度为每天北京时间 16:00（`0 8 * * *`），定时任务可能有延迟；也可在 Actions 页面手动触发。

## 版本规则

| 来源 | 标签示例 | Release |
| --- | --- | --- |
| 上游正式发版 | `v2.11.1-gabcdef123456-custom-build` | 正式版，可设为 Latest |
| 普通提交 | `v2.11.1-dev-gfedcba654321-custom-build` | Pre-release，不影响 Latest |

- 标签中的 12 位 SHA 是被编译的上游提交。
- 普通提交的版本前缀取该提交可达的最近上游标签。
- 同一提交先作为普通提交构建、后来成为正式版时，会再发布一个正式版。
- 每天只处理最新正式版和 `main` 最新提交，不补建期间所有提交。
- 附件命名：`bili-sync-rs-<标签>-Linux-armv7-gnueabihf.tar.gz`。

## 维护

修改构建行为时按阶段改对应脚本：

- 调整检测范围、命名规则：`scripts/check-upstream.sh`
- 调整编译目标、打包方式：`scripts/build-armv7.sh` / `Cross.toml`
- 调整发布说明、Latest 策略：`scripts/publish-release.sh`

提交前运行自检（只验证标签与去重规则，不联网）：

```bash
bash scripts/check-upstream.sh --self-test
```

本地查看当前判定结果（需要已登录的 `gh`）：

```bash
bash scripts/check-upstream.sh
```

## 环境要求

CI 使用 Ubuntu 24.04，依赖 `git`、`gh`、`jq`、`bun`、`rustup`、`cross` 与 Docker。本地完整编译建议在 Linux 或 WSL 中执行；Windows 原生环境仅能运行 `--self-test`。
