# Farmers Grassland

一个基于 Godot 4.6 的多人联机开放世界农场游戏原型，支持 LAN 局域网联机。

## 功能特性

- **程序化地形生成** — 基于 FastNoiseLite 的大型地形（250×250），支持编辑器内地形雕刻
- **LAN 多人联机** — 基于 ENet 的局域网多人游戏，支持 Host/Join
- **互动草地系统** — 使用 [SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured) 插件，草地随风摆动，玩家走过时草会弯曲
- **水面着色器** — 带波浪、流动、泡沫效果的实时水面
- **第一人称控制** — WASD 移动，Shift 冲刺，Space 跳跃，鼠标控制视角
- **地形雕刻插件** — 编辑器内实时笔刷雕刻地形高度

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
│   └── terrain_sculpt/        # 地形雕刻编辑器插件
├── scenes/
│   ├── lobby.tscn             # 联机大厅
│   ├── grassland.tscn         # 主游戏场景
│   └── player.tscn            # 玩家角色
├── scripts/
│   ├── terrain_generator.gd   # 程序化地形生成
│   ├── water_surface.gd       # 水面生成
│   ├── player.gd              # 第一人称控制器
│   ├── player_sync.gd         # 多人同步
│   ├── game_manager.gd        # 游戏管理/玩家生成
│   └── lobby_ui.gd            # 大厅 UI 逻辑
└── shaders/
    ├── grass_terrain.gdshader  # 地形着色器
    └── water.gdshader          # 水面着色器
```

## 画草指南

项目使用 SimpleGrassTextured 插件在编辑器中手动绘制草地：

1. 打开 `grassland.tscn`
2. 在场景树中选择 **Grass** 节点
3. 使用 3D 视口上方出现的画笔工具在地形上涂画
4. 调整密度、半径、缩放等参数
5. 完成后可通过菜单 **Bake height map** 优化运行时性能

## 技术栈

- **引擎**: Godot 4.6 (GL Compatibility)
- **物理**: Jolt Physics
- **网络**: ENet Multiplayer
- **草地**: SimpleGrassTextured 插件
- **着色器**: GLSL (Godot Shading Language)

## 许可证

本项目代码部分使用 MIT 许可证。SimpleGrassTextured 插件遵循其自身的 MIT 许可证。
