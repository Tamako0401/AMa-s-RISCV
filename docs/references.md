# 参考项目

做手势控制游戏时查到的先例和可借鉴的工程。2026-10 整理。

## 视觉手势控制游戏的先例

| 先例 | 怎么识别 | 游戏怎么设计 | 对我们的启发 |
| --- | --- | --- | --- |
| [EyeToy](https://en.wikipedia.org/wiki/EyeToy) (PS2, 2003, 商业产品) | 普通彩色摄像头, 主要靠帧差: 哪块像素变了 | 屏幕上放"触发区", 玩家的画面叠在游戏上, 手挥过某区就算碰到。[EyeToy: Play](https://en.wikipedia.org/wiki/EyeToy:_Play) 12 个小游戏: 跟节奏拍圆盘 (Beat Freak)、擦窗户 (Wishi Washi) 等; 菜单也是挥手选 | 最成熟的先例, 而且算法最便宜 (帧差 + 区域计数), 不需要认出"手"; 游戏要围绕"碰区域"设计, [游戏列表](https://en.wikipedia.org/wiki/List_of_games_compatible_with_EyeToy) |
| Kinect (Xbox 360/One, 商业产品) | 深度摄像头 + 骨架跟踪 | Fruit Ninja Kinect、Kinect Adventures: 连续的位置和挥动 | 有深度信息, 我们没有; 但说明"挥砍、躲避"类玩法成立 |
| 摄像头贪吃蛇 ([cnb](https://cnb.cool/1255027942/XingTeam-2025/SnakeGamewithCVCamera/-/blob/main/README.md)) | MediaPipe 手部关键点, 食指位置 | 食指移动控制蛇头方向, 摄像头画面做背景 | 网页版作者反馈: 用拳头方向控制不顺滑, 打算改成手掌方向 |
| 手势 Pong ([教程](https://toptechboy.com/ai-for-everyone-developing-a-gesture-based-arcade-game-based-on-mediapipe-and-python/)) | MediaPipe, 食指位置 | 食指高度控制挡板 | 连续位置控制, 最直接 |
| 手势拖拽解谜 ([项目](https://chettra.is-a.dev/projects/hand-gesture-puzzle/)) | 拇指-食指距离 (按手的大小归一化) 判断捏合 | 捏住图形拖到移动目标上, 5 关逐渐变小变快 | "捏合"是比握拳更稳的离散动作 |
| 手势映射按键 ([HandController](https://github.com/Zeus7768/HandController)、[OpenCV 键盘](https://cspub-ijcisim.org/index.php/ijcisim/article/view/5467)) | 手的倾斜 / 手指位置 → WASD | 套在现成游戏上 | 套现成游戏体验一般; 降分辨率是提帧率的常用办法 |

结论:
- 成熟的都是**连续位置** (Pong、挡板、飞机) 或**碰区域 / 挥动** (EyeToy、水果忍者) 玩法。
- 搜到的资料里没有手势玩格斗、精确射击、平台跳跃 (马里奥) 的成功例子: 这类要求按键时机精确。
- 几乎所有项目都提到光照和背景影响识别, 演示要控制场景。

## FPGA 上的手势识别

| 项目 | 平台 | 方法 |
| --- | --- | --- |
| [手部识别系统](https://www.researchgate.net/publication/308818686_Hardware_implementation_for_a_hand_recognition_system_on_FPGA) | Cyclone II, 全部硬件 | YCbCr + 区域生长分割, 形态学, 按手指状态建模 |
| [实时手势识别](https://www.sciencedirect.com/science/article/pii/S2212017312005580) | Virtex-2 Pro, Verilog | 肤色分割 + 形状特征, 10 种手势 |
| [OV7670 手势识别](https://www.researchgate.net/publication/320652225_Gesture_recognition_using_FPGA_and_OV7670_camera) | FPGA + OV7670, VHDL | 肤色分割 |
| [FPGA-Hand-Gesture-Classification](https://github.com/Zaina059/FPGA-Hand-Gesture-Classification) | FPGA, VHDL, 开源 | YCrCb 肤色 → 形态学 → 轮廓 → 24 个手工特征 → 决策树, 14 类 |
| [正点原子石头剪刀布](https://blog.csdn.net/2301_76227168/article/details/128636629) | 正点原子板 + OV5640 | 面积周长比判断 3 种手势 |
| [OV5640 肤色识别](https://blog.csdn.net/weixin_46423500/article/details/119781770) | Cyclone + OV5640 | YCbCr 肤色阈值, 含工程 |
| [FPGA+STM32 图像平台](https://github.com/x-hao-v/fpga-stm32-image-processing-platform) | FPGA + STM32 + OV5640, HDMI 输出 | 肤色检测; 用**红色标记**的运动控制虚拟物体上下左右移动 |

## sprite / 图块引擎

| 项目 | 要点 |
| --- | --- |
| [FPGA Royale](https://fpga.mit.edu/videos/2023/team21/report.pdf) (MIT 6.205, 2023) | HDMI 720p, 74.25 MHz 像素时钟, 60 帧最多 64 个精灵; 精灵图存调色板索引 + 单独调色板 |
| [rastrgrafx](https://github.com/toivoh/rastrgrafx) | 图块地图平滑滚动 + 精灵, 256 色调色板, 每个精灵子调色板 |
| [RISCBoy](https://zeli.app/story/48876245) | 自制 RISC-V CPU + 图形流水线的掌机 (iCE40), 架构最接近我们 |
| [2D Game Console](https://www.allaboutcircuits.com/ip-cores/uncategorized/2d-game-console/) | DE2-115, VGA, 16 个 16×16 精灵 + 一张背景 |

## 紫光平台

- [2023 集创赛紫光同创杯一等奖](https://github.com/flytt-away/FPGA-Video-Capture): HDMI + 双目 OV5640 采集, YOLO 识别。
- 盘古 50K 随板例程 (本机 `~/fpga/pangu50k-materials-qqn3lqz8/盘古50K开发板资料/`, 不进仓库):
  - `盘古50K开发板/2_Demo/05_hdmi_test`、`06_hdmi_loop`: HDMI 输出、HDMI 输入环回;
  - `盘古50K开发板/2_Demo/10_HDMI_DDR3_OV5640_test`: 双目 OV5640 → DDR3 → HDMI, 说明在
    `1_Demo_document/实验例程说明篇/10_OV5640双目摄像头实验例程v1.pdf` (OV5640 配成 720p@30 RGB565);
  - `OV5640资料/原理图/DOUBLE-DVP-OV5640-1113.pdf`: 双目模块原理图;
  - `1_Demo_document/工具使用篇/05_FPGA&CPLD的下载与固化_v1.1.pdf`: flash 固化 (界面操作)。
