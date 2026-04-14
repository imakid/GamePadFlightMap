# GamePadFlightMap

A gamepad-friendly flight point list overlay for World of Warcraft's taxi/flight map.

魔兽世界飞行地图的手柄友好型飞行点列表面板插件。

---

## Features / 功能

- Scrollable flight point list panel next to the native flight map  
  在原生飞行地图旁显示可滚动的飞行点列表面板
- Click to highlight route on map, double-click to fly  
  单击高亮路线，双击直接飞行
- Gamepad D-pad navigation support (up/down single step, left/right jump 5 steps)  
  手柄方向键导航支持（上/下逐项移动，左/右跳转5项）
- Search filter for flight points  
  飞行点搜索过滤
- Toggle unreachable flight points visibility  
  切换不可达飞行点的显示/隐藏
- Smart sorting: reachable first → most-used → nearest → alphabetical  
  智能排序：可达优先 → 使用频率高优先 → 距离近优先 → 字母序
- Flight frequency tracking and display  
  飞行频率追踪与显示
- Filter out current location automatically  
  自动过滤当前所在地
- ESC key to close  
  按 ESC 关闭

## Installation / 安装

1. Download or clone this repository / 下载或克隆本仓库
2. Copy the `GamePadFlightMap` folder to your WoW addon directory:  
   将 `GamePadFlightMap` 文件夹复制到 WoW 插件目录：
   - **Retail**: `World of Warcraft\_retail_\Interface\AddOns\`
   - **Classic**: `World of Warcraft\_classic_\Interface\AddOns\`
3. Restart WoW or reload UI (`/reload`) / 重启 WoW 或重载界面（`/reload`）

## Usage / 使用方法

The overlay automatically appears when talking to a flight master.  
与飞行管理员对话时，面板会自动出现。

### Mouse Controls / 鼠标操作

| Action / 操作 | Behavior / 行为 |
|---------------|-----------------|
| Hover / 悬停 | Highlight item in list / 高亮列表项 |
| Left Click / 左键单击 | Select & draw route on map / 选中并在地图上绘制路线 |
| Double Click / 双击 | Fly to selected point / 飞往选中的飞行点 |
| Right Click / 右键单击 | Close flight map / 关闭飞行地图 |
| Scroll Wheel / 滚轮 | Navigate up/down / 上下滚动列表 |

### Gamepad Controls / 手柄操作

| Button / 按键 | Behavior / 行为 |
|---------------|-----------------|
| D-Pad Up/Down / 方向键上/下 | Navigate list / 逐项移动 |
| D-Pad Left/Right / 方向键左/右 | Jump 5 items / 跳转5项 |
| A / PAD1 | Fly to selected / 飞往选中点 |
| B / PAD2 | Close flight map / 关闭飞行地图 |
| X / PAD3 | Toggle unreachable filter / 切换不可达过滤 |
| Y / PAD4 | Focus search box / 聚焦搜索框 |
| Left Stick / 左摇杆 | Navigate list / 移动列表 |

### Slash Commands / 斜杠命令

```
/gpfm debug      - Toggle debug mode / 切换调试模式
/gpfm show       - Force show overlay / 强制显示面板
/gpfm hide       - Force hide overlay / 强制隐藏面板
/gpfm toggle     - Toggle overlay / 切换面板显示
/gpfm stats      - Show flight statistics / 显示飞行统计
/gpfm resetstats - Reset flight statistics / 重置飞行统计
```

## Configuration / 配置

Saved variables are stored in `GamePadFlightMapDB`:  
保存的变量存储在 `GamePadFlightMapDB` 中：

- `enabled` - Enable/disable the addon (default: true) / 启用/禁用插件（默认：启用）
- `debugMode` - Enable debug logging (default: false) / 启用调试日志（默认：关闭）
- `flightStats` - Flight frequency data per node name / 每个飞行点的飞行频率数据

## Compatibility / 兼容性

- WoW Retail 11.x (Interface 120005)
- Optional dependency / 可选依赖: [ConsolePort](https://www.curseforge.com/wow/addons/consoleport) for enhanced gamepad support / 以获得更好的手柄支持

## License / 许可证

MIT
