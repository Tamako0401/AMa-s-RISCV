# RIB ↔ AXI 协议桥

`rtl/core/axi_bridge.v` 把 **RIB** 与 **AXI4 / AXI4-Lite** 对接，
用途是让 AXI 接口的厂商控制器（例如 DDR3 控制器）能挂进 RIB 的地址空间，
让 CPU 像访问普通存储器一样访问它。

RIB 从设备侧的端口命名与 `rtl/perips/spi.v`、`rtl/perips/gpio_matrix.v` 完全一致，
因此它可以像普通外设一样接进 RIB 的任意从设备槽位。

## 为什么只发单拍事务

| 考虑 | 说明 |
| --- | --- |
| RIB 没有 burst | 每次事务只搬 4 字节，`arlen` 再大也用不上 |
| 兼容两种从设备 | 单拍（`len=0`、`burst=INCR`）的 AXI4 语义与 AXI4-Lite 一致 |
| 简化实现 | 不用处理 burst 拆包、窄传输首末拍、`rlast` 序列 |

代价是**用不上 DDR3 的 burst 带宽**。将来若要吃满 DDR3 带宽，需要先让 RIB 支持 burst。

## 字节使能的处理方式

RIB 的 `sel_i` 是**按 32 位字对齐**的字节通道掩码。AXI 侧不使用窄传输，
而是「**整宽传输 + WSTRB**」：

| 方向 | 做法 |
| --- | --- |
| 写 | `awaddr` 向下对齐到 AXI 数据宽度；`WSTRB` 为 `sel_i` 按地址低位平移；`WDATA` 同理 |
| 读 | `araddr` 向下对齐；读回整拍后按地址低位挑出 RIB 需要的 4 字节 |

这是简化桥的常规做法：存储控制器只把 `WSTRB` 当字节使能，普遍接受。
代价是未对齐访问会把整拍读/写过去，对存储设备无害。

## 接口

### RIB 从设备侧

| 端口 | 说明 |
| --- | --- |
| `addr_i / data_i / sel_i / we_i` | 与其它外设一致 |
| `data_o` | 读回数据；写事务回读原写数据（与简单存储器一致） |
| `req_valid_i / req_ready_o` | 空闲（`S_IDLE`）时才接受请求 |
| `rsp_valid_o / rsp_ready_i` | 响应寄存后返回，保持到 `rsp_ready_i` |
| `error_o` | AXI 返回非 `OKAY`、或读到多拍 / `rlast=0` 时置位；**粘滞，只能靠复位清除** |

### AXI 主设备侧

完整的 AR/R、AW/W/B 五个通道。`arlen/awlen` 恒为 0，`arburst/awburst` 恒为
`INCR`，`arid/awid` 恒为 0，`wlast` 恒为 1。cache / protection / region / QoS
类信号不引出。

### 参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `AXI_ID_WIDTH` | 4 | ID 恒为 0，宽度按从设备要求填 |
| `AXI_ADDR_WIDTH` | 32 | **只验证过 32** |
| `AXI_DATA_WIDTH` | 32 | **支持 32 与 64**；64 位下按地址低位选择 4 字节通道 |

## 前提与限制

- **时钟**：假定 AXI 侧与 RIB 侧**同频同相**。若控制器 AXI 接口在另一个时钟域，
  必须在外部加异步 FIFO，或把本模块改成双时钟。
- **单事务在飞**：同一时刻只允许一笔 AXI 事务，与 RIB 的单事务语义一致。
  不支持 ID 重排与独占访问。
- **AXI_ADDR_WIDTH 只验证过 32**；若从设备地址位宽小于 32，需要调整地址对齐
  表达式。

## 接入真实控制器

1. 在 PDS 的 IP 生成器里确认控制器 IP 的**接口类型**（AXI4-Lite / AXI4 / native）、
   **数据位宽**和**是否与 CPU 同频**。
2. 按上表设置 `axi_bridge` 的参数，把 AXI 侧直接连到 IP 的从设备端口。
3. 在 `rtl/soc_top/soc_top.v` 里把这个桥接进 RIB 的一个空闲槽位。`s0` ROM、`s1` RAM、`s4` 外设子总线（GPIO 矩阵/UART/SPI/SYSCTL 在
   `rtl/core/periph_bus.v` 下按 `addr[15:12]` 再分），**`s2`（`0x2000_0000`）与
   `s3`（`0x3000_0000`）空闲**，适合放大容量设备。注意 RIB 一共只有 `s0`~`s4`
   五档，细粒度外设应挂到 `s4` 的子总线，而不是各占一档。
4. `error_o` 接进某个状态寄存器，供软件查询。

**综合时**：IP 由 PDS 的 IP 生成器产出并加入工程，`axi_bridge.v` 直接参与综合。

## 仿真怎么回归

| 文件 | 作用 |
| --- | --- |
| `tests/reusable/axi_slave_model.sv` | AXI4 从设备模型：一块字存储器 + 可配置读写延迟 + 可注入 `SLVERR` |
| `tests/reusable/axi_bridge_tb.sv` | 桥的组件测试，同时例化 32 位与 64 位两个实例 |

模型会对 burst（`arlen/awlen != 0`）直接 `$fatal`，**把它当断言用**：这正是
我们期望 `axi_bridge` 永远不会发出的东西。

## 验证范围

覆盖并已通过（47 个用例）：

- 字 / 半字 / 单字节读写，四种字节通道各来一遍
- 读延迟与写延迟：桥必须等待而不是抢拍
- RIB 响应背压：响应保持 5 拍期间 `valid` 与数据都不能变，且不能重复
- 单次执行：每笔 RIB 事务**恰好**产生一笔 AXI 事务（AR/AW/W 计数器核对）
- AXI 数据宽度 32 与 64 两种取值的字节通道定位（含地址平移到高位通道的单字节写）
- 非 `OKAY` 响应上报到 `error_o`，且粘滞不被后续正常事务清除

**未覆盖**：真实 DDR3 控制器 IP、真实 DDR3 时序、上电校准、跨时钟域、
`AXI_ADDR_WIDTH` 非 32、RIB 侧 burst。**数字仿真通过不代表上板可用**；
DDR3 的校准与引脚约束必须在实机上验证。
