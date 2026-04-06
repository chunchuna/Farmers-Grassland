# Farmers Grassland

一个基于 Godot 4.6 的多人联机开放世界农场游戏原型，支持 LAN 局域网联机。

## 功能特性

- **Terrain3D 地形** — 使用 [Terrain3D](https://github.com/TokisanGames/Terrain3D) 高性能 C++ 地形插件，支持编辑器内雕刻、纹理绘制、LOD
- **LAN 多人联机** — 基于 ENet 的局域网多人游戏，支持 Host/Join
- **互动草地系统** — 使用 [SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured) 插件，草地随风摆动，玩家走过时草会弯曲
- **第一人称控制** — WASD 移动，Shift 冲刺，Space 跳跃，鼠标控制视角

## 快速开始

### 环境要求

- [Godot 4.6+](https://godotengine.org/download) (GL Compatibility 渲染器)
- Windows / macOS / Linux

### 运行项目

1. 克隆仓库：
   ```bash
   git clone https://github.com/chunchuna/Farmers-Grassland.git
   ```
2. 用 Godot 4.6+ 打开 `project.godot`
3. 按 F5 运行

### 联机测试

1. **调试 → 运行多个实例** 设为 **2**
2. 按 F5，第一个窗口点 **Host**
3. 第二个窗口输入 `127.0.0.1` 点 **Join**

## 操作说明

| 按键 | 功能 |
|------|------|
| W/A/S/D | 移动 |
| Shift | 冲刺 |
| Space | 跳跃 |
| 鼠标 | 视角 |
| Esc | 释放/捕获鼠标 |

## 项目结构

```
├── addons/
│   ├── simplegrasstextured/   # 草地插件 (第三方)
│   └── terrain_3d/            # Terrain3D 地形插件 (第三方)
├── scenes/
│   ├── lobby.tscn             # 联机大厅
│   ├── grassland.tscn         # 主游戏场景
│   └── player.tscn            # 玩家角色
└── scripts/
    ├── player.gd              # 第一人称控制器
    ├── player_sync.gd         # 多人同步
    ├── game_manager.gd        # 游戏管理/玩家生成
    └── lobby_ui.gd            # 大厅 UI 逻辑
```

## 地形编辑

选中场景树中的 **Terrain3D** 节点后，编辑器上方会出现 Terrain3D 工具栏：

1. **Region** — 先添加一个 Region（地形区块），这是绘制的前提
2. **Sculpt** — 雕刻地形高度（升高/降低/平滑）
3. **Paint** — 绘制地形纹理（需先在 Asset Dock 中添加纹理）
4. **Foliage** — Terrain3D 自带的植被实例化系统

## 画草指南

使用 SimpleGrassTextured 插件在 Terrain3D 地形上绘制草地：

1. 打开 `grassland.tscn`
2. 确保 Terrain3D 已有地形数据（至少一个 Region）
3. 选择 **Grass** 节点
4. 使用 3D 视口上方出现的画笔工具在地形上涂画
5. 调整密度、半径、缩放等参数

## 技术栈

- **引擎**: Godot 4.6 (GL Compatibility)
- **物理**: Jolt Physics
- **网络**: ENet Multiplayer
- **地形**: Terrain3D (C++ GDExtension)
- **草地**: SimpleGrassTextured 插件

## 许可证

本项目代码部分使用 MIT 许可证。Terrain3D 和 SimpleGrassTextured 插件各自遵循 MIT 许可证。
