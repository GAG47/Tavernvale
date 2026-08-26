# Tavernvale v0 / Project Foundation

- Version: v0 / Project Foundation
- Date: 2026-08-26
- Commit: Pending

## 目标

建立 `scripts/` 与 `docs/` 项目结构、长期开发规则和独立开发日志制度，并在不改变算法行为的前提下迁移已完成的 Spatial Skeleton Runtime 代码。

## 修改内容

- 建立 `scripts/world/worldgen/` Runtime 目录体系。
- 将已有 WorldGen Random 与 Spatial 脚本及其 Godot UID 从 `world/worldgen/` 原样迁移到 `scripts/world/worldgen/`。
- 建立 `docs/design/`、`docs/development/` 和 `docs/logs/`。
- 新增长期开发规则和统一日志格式。
- 补录 v1.0 Spatial Skeleton 与 v1.0.1 Spatial Topology Fix 历史日志。
- 检查测试、Debug Scene、主场景和资源引用；现有代码通过 `class_name` 使用 Runtime 类型，没有需要改写的硬编码 `res://world/...` 引用。

## 修改文件

- 移动 `world/worldgen/random/` 至 `scripts/world/worldgen/random/`。
- 移动 `world/worldgen/spatial/` 至 `scripts/world/worldgen/spatial/`。
- 新增 `docs/design/.gitkeep`。
- 新增 `docs/development/development-rules.md`。
- 新增 `docs/logs/2026-08-26_v1.0_spatial-skeleton.md`。
- 新增 `docs/logs/2026-08-26_v1.0.1_spatial-topology-fix.md`。
- 新增本日志。

## 关键实现

- `scripts/` 只保存参与 Runtime 的代码；`tests/` 保持测试与 Debug Scene；`docs/` 不参与 Runtime。
- 一项正式开发任务必须对应 `docs/logs/` 下的一份独立日志。
- 8 个迁移后的 Runtime `.gd` 文件与 `47ec1ca` 对应旧路径文件逐一进行 Git Blob Hash 比较，内容完全一致。
- `.gd.uid` 与脚本一并迁移，保留 Godot 资源身份。

## 测试

- Godot 4.7.1 headless editor 完成资源扫描和全局类注册，退出码为 0；沙箱环境禁止编辑器 TCP 监听，因此输出了 `_inet_open` / `ERR_CANT_CREATE` 环境警告，没有脚本或资源错误。
- 执行 `godot --headless --path . --script res://tests/worldgen/spatial/spatial_generator_test.gd`：10/10 测试组通过。
- 默认图结果：10000 Cells、20002 Vertices、30001 Edges、383 Border Cells，生成及 Validator 用时 735 ms。
- 执行项目主场景 headless 启动检查：Spatial Debug Scene 正常启动，无脚本或资源路径错误。
- Spatial Validator 通过；迁移前后 Runtime 源文件内容完全相同，默认拓扑统计保持一致。

## 已知问题

- 当前沙箱不允许 Godot headless editor 创建本地 TCP 监听端口，会输出环境警告；不影响资源扫描、测试或项目运行，非项目代码问题。

## 设计偏差

无。
