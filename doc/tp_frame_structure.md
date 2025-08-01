# KNX TPUART帧结构分析

> 本文档基于KNXD源代码深入分析KNX TPUART帧的结构和解析逻辑

## 目录

1. [概述](#概述)
2. [标准帧结构](#1-标准帧结构) 
3. [扩展帧结构](#2-扩展帧结构)
4. [地址编码机制](#3-地址编码机制)
5. [LSDU数据结构](#4-lsdu数据结构)
6. [长度字段编码](#5-长度字段编码)
7. [优先级和校验](#6-优先级和校验)
8. [代码参考](#7-代码参考)

## 概述

KNX TPUART (Twisted Pair Universal Asynchronous Receiver Transmitter) 支持两种帧格式：
- **标准帧 (Standard Frame)**: 适用于短数据传输 (LSDU ≤16字节)
- **扩展帧 (Extended Frame)**: 适用于长数据传输 (LSDU ≤256字节)

**帧类型选择**：
- 帧格式由控制字段第一个字节的Bit7决定：
  - Bit7 = 1 → 标准帧
  - Bit7 = 0 → 扩展帧
- KNXD根据LSDU长度自动选择帧格式：
  - LSDU ≤ 16字节 → 使用标准帧
  - LSDU > 16字节 → 使用扩展帧

---

## 1. 标准帧结构

### 1.1 帧格式

```
总长度: 7字节 + LSDU长度 + 1字节校验和 (最大22字节)

偏移  字段名             长度    说明
0     控制字段           1字节   帧控制信息
1-2   源地址             2字节   发送设备地址
3-4   目标地址           2字节   接收设备地址  
5     NPDU头             1字节   网络层头部
6-N   LSDU数据           0-15字节 传输层+应用层数据
N+1   校验和             1字节   XOR校验
```

### 1.2 字段详解

#### 控制字段 (字节0)
```
Bit 7    [F] 帧格式:      1=标准帧
Bit 6    [R] 保留位:      固定为0
Bit 5    [R] 重复标志:    0=重复帧, 1=非重复帧
Bit 4    [C] 确认位:      固定为1 (L_Data标识)
Bit 3-2  [PP] 优先级:     00=系统, 01=普通, 10=紧急, 11=低
Bit 1    [A] 确认标志:    0=不需要确认, 1=需要确认
Bit 0    [S] 系统位:      系统相关控制位
```

#### 源地址和目标地址 (字节1-4)

KNX 系统使用两种类型的16位地址：

**源地址**: 总是个体地址，标识发送设备
- **个体地址格式**: `区域.线路.设备` (如 1.1.15)
- **编码方式**: `(区域<<12) | (线路<<8) | 设备`
```
Bit:  15 14 13 12 | 11 10  9  8 |  7  6  5  4  3  2  1  0
Field:  区域(4位)  |  线路(4位)  |       设备(8位)
Range:    0-15     |    0-15     |        0-255
示例:  0001       |   0001      |      00001111  = 1.1.15
```

**目标地址**: 根据地址类型位(AT)可以是个体地址或组地址
- **组地址格式**: `主组/中组/子组` (如 1/2/3)
- **编码方式**: `(主组<<11) | (中组<<8) | 子组`
```
Bit:  15 14 13 12 11 | 10  9  8 |  7  6  5  4  3  2  1  0
Field:   主组(5位)   |  中组(3位) |        子组(8位)
Range:     0-31      |    0-7     |         0-255
示例:  00001        |   010     |     00000011  = 1/2/3
```

#### NPDU头 (字节5)
```
Bit 7     [G] 地址类型:    1=组地址, 0=个体地址
Bit 6-4   [HHH] 跳数:     网络跳数计数器 (0-7)
Bit 3-0   [LLLL] 长度:    LSDU长度-1 (0-15，实际LSDU长度1-16字节)
```

**长度字段详解**:
- **字段值范围**: 0-15 (0x0-0xF，4位)
- **对应LSDU长度**: 1-16字节 (字段值+1)
- **实际最小长度**: 2字节 (KNX协议要求: TPCI+APCI)
- **编码公式**: 字段值 = LSDU实际长度 - 1
- **帧格式选择**: LSDU长度≤16字节时使用标准帧，超过16字节时使用扩展帧

**编码示例**:
- 字段值0 (0000₂) → LSDU长度1字节 (理论最小，实际不可用)
- 字段值1 (0001₂) → LSDU长度2字节 (实际最小: TPCI+APCI)  
- 字段值15 (1111₂) → LSDU长度16字节

### 1.3 示例帧分析

#### 示例1: A_GroupValue_Write 6位数据
```
BC 11 01 02 03 8F 81 0F XX
```

**字段解析:**
- `BC` (10111100): 标准帧, 非重复, 普通优先级
- `11 01`: 源地址 = 0x1101  
- `02 03`: 目标地址 = 0x0203
- `8F` (10001111): 组地址, 跳数0, LSDU长度2字节
- `81 0F`: LSDU数据
  - `81`: TPCI=00(T_Data_Group) + APCI高2位=00, APCI低8位=10000001  
  - `0F`: APCI中4位=0001 + 6位数据=1111 (值15)
  - 完整APCI=0x080 (A_GroupValue_Write)
  - 数据值=15 (存储在APCI低6位)
- `XX`: 校验和

#### 示例2: A_GroupValue_Write 多字节数据  
```
BC 11 01 02 03 91 80 12 34 XX
```

**字段解析:**
- `BC` (10111100): 标准帧, 非重复, 普通优先级
- `11 01`: 源地址 = 0x1101
- `02 03`: 目标地址 = 0x0203  
- `91` (10010001): 组地址, 跳数0, LSDU长度4字节
- `80 12 34`: LSDU数据
  - `80`: TPCI=00(T_Data_Group) + APCI高2位=00, APCI低8位=10000000
  - 完整APCI=0x080 (A_GroupValue_Write)
  - `12 34`: 2字节数据=0x1234 (独立存储)
- `XX`: 校验和

---

## 2. 扩展帧结构

### 2.1 帧格式

```
总长度: 8字节 + LSDU长度 + 1字节校验和 (最大264字节)

偏移  字段名             长度    说明
0     控制字段           1字节   帧控制信息
1     NPDU头扩展         1字节   网络层头部(扩展)
2-3   源地址             2字节   发送设备地址
4-5   目标地址           2字节   接收设备地址
6     数据长度           1字节   LSDU字节数 (0-255)
7-N   LSDU数据           0-255字节 传输层+应用层数据
N+1   校验和             1字节   XOR校验
```

### 2.2 字段详解

#### 控制字段 (字节0)
与标准帧相同，但Bit7=0表示扩展帧

#### NPDU头扩展 (字节1)
```
Bit 7     [G] 地址类型:    1=组地址, 0=个体地址
Bit 6-4   [HHH] 跳数:     网络跳数计数器 (0-7)  
Bit 3-0   [0000] 保留:    固定为0000
```

#### 数据长度 (字节6)
**字段值范围**: 0-255 (8位完整字节)  
**对应LSDU长度**: 1-256字节 (字段值+1)  
**编码公式**: 字段值 = LSDU实际长度 - 1

**与标准帧的差异**:
- 标准帧：4位长度字段，最大LSDU长度16字节
- 扩展帧：8位长度字段，最大LSDU长度256字节

---

## 3. 地址编码机制

### 3.1 地址类型判断
地址类型通过NPDU头中的AT位确定：
```c
// 标准帧中的地址类型检查 (cm_tp1.cpp:40)
l->address_type = (c[5] & 0x80) ? GroupAddress : IndividualAddress;

// 扩展帧中的地址类型检查 (cm_tp1.cpp:53)  
l->address_type = (c[1] & 0x80) ? GroupAddress : IndividualAddress;
```

### 3.2 个体地址编码
**格式**: `区域.线路.设备` (如 1.1.15 = 0x110F)

**解析代码**:
```c
// 个体地址格式化 (common.cpp:37-40)
std::string FormatEIBAddr(eibaddr_t addr) {
  sprintf(buf, "%d.%d.%d", 
          (addr >> 12) & 0xf,   // 区域: 4位 (0-15)
          (addr >> 8) & 0xf,    // 线路: 4位 (0-15)  
          addr & 0xff);         // 设备: 8位 (0-255)
}

// 个体地址解析 (common.c:50-51)
eibaddr_t readaddr(const char *addr) {
  sscanf(addr, "%u.%u.%u", &a, &b, &c);
  return (a << 12) | (b << 8) | c;
}
```

### 3.3 组地址编码  
**格式**: `主组/中组/子组` (如 1/2/3 = 0x0903)

**解析代码**:
```c
// 组地址格式化 (common.cpp:43-47)
std::string FormatGroupAddr(eibaddr_t addr) {
  sprintf(buf, "%d/%d/%d", 
          (addr >> 11) & 0x1f,  // 主组: 5位 (0-31)
          (addr >> 8) & 0x7,    // 中组: 3位 (0-7)
          addr & 0xff);         // 子组: 8位 (0-255)
}

// 组地址解析 (common.c:70-72)  
eibaddr_t readgaddr(const char *addr) {
  sscanf(addr, "%u/%u/%u", &a, &b, &c);
  return (a << 11) | (b << 8) | c;
}
```

### 3.4 地址在不同帧格式中的位置
**标准帧**:
```c
l->source_address = (c[1] << 8) | c[2];      // 字节1-2: 源地址
l->destination_address = (c[3] << 8) | c[4]; // 字节3-4: 目标地址
```

**扩展帧**:
```c  
l->source_address = (c[2] << 8) | c[3];      // 字节2-3: 源地址
l->destination_address = (c[4] << 8) | c[5]; // 字节4-5: 目标地址
```

---

## 4. LSDU数据结构

LSDU (Link Service Data Unit) 包含传输层和应用层数据，**最小长度为2字节**：

### 4.1 LSDU层次结构
```
LSDU = TPDU = TPCI + APDU + [数据]
             (1字节) (1-2字节) (0-N字节)
             
总最小长度: 2字节 (TPCI + APCI)
```

### 4.2 数据存储格式

KNX协议支持两种数据存储格式，根据数据长度自动选择：

#### 6位数据格式 (≤6位数据)
**适用于**: 小数据量，如开关状态、调光值等
**LSDU长度**: 2字节
**数据位置**: 存储在APCI字段的低6位中

```
字节0: [TPCI高6位][APCI高2位]
字节1: [APCI中4位][6位数据]
       10xxxxdd dddd
       |  |   |
       |  |   └── 6位数据 (0-63)
       |  └────── APCI中间位
       └───────── APCI标识位
```

**编码示例**:
```c
// 发送6位数据 (值=15)
pdu[0] = 0x00;           // TPCI=00 (T_Data_Group) + APCI高2位=00
pdu[1] = 0x80 | 0x0F;    // APCI=0x80 (Write) + 数据=0x0F
// 完整APCI = 0x080 + 0x0F = 0x08F (A_GroupValue_Write + 6bit数据)
```

#### 多字节数据格式 (>6位数据)
**适用于**: 较大数据量，如温度值、时间等
**LSDU长度**: 3字节及以上
**数据位置**: 从字节2开始的独立数据区域

```
字节0: [TPCI高6位][APCI高2位]
字节1: [APCI低8位]
字节2: [数据字节0]
字节3: [数据字节1]
...
字节N: [数据字节N-2]
```

**编码示例**:
```c
// 发送多字节数据 (2字节温度值: 0x1234)
pdu[0] = 0x00;     // TPCI=00 (T_Data_Group) + APCI高2位=00
pdu[1] = 0x80;     // APCI低8位=0x80 (A_GroupValue_Write)
pdu[2] = 0x12;     // 数据字节0
pdu[3] = 0x34;     // 数据字节1
// 完整APCI = 0x080 (A_GroupValue_Write)
```

### 4.3 数据格式自动选择

代码中根据APDU长度自动判断数据格式：

```c
// A_GroupValue_Write_PDU::init() 和 A_GroupValue_Response_PDU::init()
bool A_GroupValue_Write_PDU::init (const CArray & c, TracePtr)
{
  if (c.size() < 2)
    return false;

  issmall = (c.size() == 2);  // 判断是否为6位数据格式
  if (issmall)
    {
      // 6位数据格式: 数据存储在APCI的低6位
      data.resize(1);
      data[0] = c[1] & 0x3f;   // 提取低6位数据
    }
  else
    {
      // 多字节数据格式: 数据从字节2开始
      data.set (c.data() + 2, c.size() - 2);
    }
  return true;
}
```

### 4.4 数据长度限制

**6位数据格式**:
- 数据范围: 0-63 (0x00-0x3F)
- 典型用途: 开关状态(0/1)、调光百分比(0-100%映射到0-63)
- LSDU长度: 固定2字节

**多字节数据格式**:
- 数据长度: 1-254字节 (受LSDU最大长度限制)
- 典型用途: 温度值、时间戳、文本数据等
- LSDU长度: 3-256字节 (2字节TPCI+APCI + 1-254字节数据)

### 4.5 TPCI (传输层协议控制信息) - 字节0
```
Bit 7-6: 传输服务类型
Bit 5-2: 序列号或其他控制位
Bit 1-0: APCI高2位
```

**传输服务类型**:
```
字节0的高6位定义传输服务类型:
- 00xxxxxx: T_Data_Group (组数据传输)
- 01xxxxxx: T_Data_Tag_Group (带标签的组数据)
- 10xxxxxx: T_Data_Individual (个体数据传输)
- 11xxxxxx: T_Data_Connected (连接型数据传输)
```

### 4.6 APCI (应用层协议控制信息) - 字节0低2位+字节1
```
10位APCI编码跨越2字节:
- APCI高2位: 字节0的低2位 (Bit 1-0)
- APCI低8位: 字节1 (可能包含6位数据)
- 完整APCI = (字节0 & 0x03) << 8 | (字节1 & 0xC0)

常见APCI值:
- 0x000: A_GroupValue_Read (组值读取)
- 0x040: A_GroupValue_Response (组值响应)  
- 0x080: A_GroupValue_Write (组值写入)
- 0x0C0: 保留用于6位数据传输
```

**APCI与数据的关系**:
- **6位数据格式**: APCI的低6位用于存储数据
- **多字节格式**: APCI完整10位用于命令标识，数据独立存储

### 4.7 实际LSDU示例

#### 示例1: A_GroupValue_Read (2字节LSDU)
```
字节0: 0x00  // TPCI=00 (T_Data_Group) + APCI高2位=00
字节1: 0x00  // APCI低8位=00000000
完整APCI: 0x000 = A_GroupValue_Read
数据: 无
```

#### 示例2: A_GroupValue_Write 6位数据 (2字节LSDU)
```
字节0: 0x00  // TPCI=00 (T_Data_Group) + APCI高2位=00  
字节1: 0x8F  // APCI中4位=1000 + 6位数据=1111 (值15)
完整APCI: 0x080 = A_GroupValue_Write
数据: 15 (存储在APCI的低6位)
```

#### 示例3: A_GroupValue_Write 多字节数据 (4字节LSDU)
```
字节0: 0x00  // TPCI=00 (T_Data_Group) + APCI高2位=00
字节1: 0x80  // APCI低8位=10000000
字节2: 0x12  // 数据字节0
字节3: 0x34  // 数据字节1  
完整APCI: 0x080 = A_GroupValue_Write
数据: 0x1234 (独立存储)
```

---

## 5. 长度字段编码

基于KNXD源代码分析，KNX TPUART帧中的长度字段取值范围确认如下：

### 5.1 标准帧长度字段 [LLLL] 
- **位宽**: 4位 (NPDU头字节5的Bit 3-0)
- **字段值范围**: 0-15 (0x0-0xF)
- **对应LSDU长度**: 1-16字节
- **编码公式**: 字段值 = LSDU实际长度 - 1
- **解码公式**: LSDU长度 = 字段值 + 1

**代码验证**:
```c
// 编码时 (cm_tp1.cpp:90-91)
uint8_t len = p->lsdu.size() - 1;  // 计算字段值: LSDU长度-1
if (len <= 0x0f) {                 // 字段值≤15 (0xF)，即LSDU≤16字节

// 解码时 (cm_tp1.cpp:42)  
uint8_t len = (c[5] & 0x0f) + 1;   // 恢复LSDU长度: 字段值+1
```

**取值对应表**:
| 字段值 | 十六进制 | 二进制 | LSDU长度 | 帧总长度 |
|--------|----------|--------|----------|----------|
| 0      | 0x0      | 0000   | 1字节    | 8字节    |
| 1      | 0x1      | 0001   | 2字节    | 9字节    |
| ...    | ...      | ...    | ...      | ...      |
| 15     | 0xF      | 1111   | 16字节   | 23字节   |

### 5.2 扩展帧长度字段
- **位宽**: 8位 (专用长度字节6) 
- **字段值范围**: 0-255 (0x00-0xFF)
- **对应LSDU长度**: 1-256字节
- **编码/解码**: 与标准帧相同，字段值 = LSDU长度 - 1

### 5.3 帧格式选择
KNXD根据LSDU长度自动选择帧格式：
- LSDU ≤ 16字节 → 标准帧
- LSDU > 16字节 → 扩展帧

### 5.4 帧总长度计算公式
```
标准帧: 7 + LSDU长度 + 1 = LSDU长度 + 8
扩展帧: 8 + LSDU长度 + 1 = LSDU长度 + 9
```

### 5.5 LSDU长度限制与编码

#### 标准帧长度处理
```c
// 发送时检查 (cm_tp1.cpp:91-92)
uint8_t len = p->lsdu.size() - 1;  // 计算长度-1
if (len <= 0x0f) {                 // 长度-1必须≤15，即LSDU≤16字节
  // 使用标准帧，长度字段存储 (LSDU长度-1)
  pdu[5] = ((len & 0x0f));         // 长度-1编码到低4位
}

// 接收时解析 (cm_tp1.cpp:42-43)  
uint8_t len = (c[5] & 0x0f) + 1;   // 从长度字段恢复真实LSDU长度
if (len + 7 != c.size())           // 验证帧总长度
  return nullptr;
```

**取值范围**:
- 长度字段值: 0-15 (4位)
- 实际LSDU长度: 1-16字节 (长度字段+1)
- 标准帧总长度: 8-23字节

#### 扩展帧长度处理
```c  
// 扩展帧直接存储真实LSDU长度 (cm_tp1.cpp:117,58)
pdu[6] = (p->lsdu.size() - 1) & 0xff;  // 发送: 存储长度-1
uint8_t len = c[6] + 1;                // 接收: 恢复真实长度
```

**取值范围**:
- 长度字段值: 0-255 (8位，存储LSDU长度-1)
- 实际LSDU长度: 1-256字节
- 扩展帧总长度: 10-265字节

#### 帧格式选择逻辑
```c
// 自动选择帧格式 (cm_tp1.cpp:90-92)
uint8_t len = p->lsdu.size() - 1;
if (len <= 0x0f) {
  // LSDU ≤ 16字节: 使用标准帧
} else {
  // LSDU > 16字节: 使用扩展帧  
}
```

---

## 6. 优先级和校验

### 6.1 优先级定义

KNX定义了4个优先级别：

| 值  | 二进制 | 优先级名称 | 用途           |
|-----|--------|-----------|----------------|
| 0   | 00     | 系统      | 系统管理通信   |
| 1   | 01     | 普通      | 一般应用通信   |
| 2   | 10     | 紧急      | 报警等紧急通信 |
| 3   | 11     | 低        | 后台传输等     |

### 6.2 校验和计算

使用XOR校验：
```
校验和 = 字节0 ⊕ 字节1 ⊕ ... ⊕ 字节N
```

接收端验证所有字节(包括校验和)的XOR结果应为0。

### 6.3 帧验证

#### 控制字段验证
接收时检查固定位模式：
- 掩码 `0x53` (01010011) 检查Bit6, Bit4, Bit1, Bit0
- 期望值 `0x10` (00010000) 要求Bit6=0, Bit4=1, Bit1=0, Bit0=0

#### 扩展帧特殊验证
- NPDU头扩展的低4位必须为0

---

## 7. 代码参考

以下代码引用来自KNXD项目，展示了实际的解析和构造逻辑：

### 7.1 帧类型识别
```cpp
// tpuart.cpp:380
bool ext = !(in[0] & 0x80);  // 第0字节Bit7决定帧类型
```

### 7.2 标准帧解析
```cpp
// cm_tp1.cpp:31-46
l->frame_format = (c[0] & 0x80) ? 1 : 0;         // Bit 7: 帧格式
l->repeated = (c[0] & 0x20) ? 0 : 1;             // Bit 5: 重复标志  
l->priority = static_cast<EIB_Priority>((c[0] >> 2) & 0x3);  // Bit 3-2: 优先级
l->source_address = (c[1] << 8) | (c[2]);       // 字节1-2: 源地址
l->destination_address = (c[3] << 8) | (c[4]);  // 字节3-4: 目标地址
l->address_type = (c[5] & 0x80) ? GroupAddress : IndividualAddress;  // Bit 7: 地址类型
l->hop_count = (c[5] >> 4) & 0x07;              // Bit 6-4: 跳数
uint8_t len = (c[5] & 0x0f) + 1;                // Bit 3-0: 数据长度-1
l->lsdu.set(c.data() + 6, len);                 // 字节6开始: LSDU数据
```

### 7.3 扩展帧解析
```cpp
// cm_tp1.cpp:48-71
if ((c[1] & 0x0f) != 0)  // 字节1低4位必须为0
  return nullptr;
l->address_type = (c[1] & 0x80) ? GroupAddress : IndividualAddress;  // Bit 7: 地址类型
l->hop_count = (c[1] >> 4) & 0x07;              // Bit 6-4: 跳数
l->source_address = (c[2] << 8) | (c[3]);       // 字节2-3: 源地址
l->destination_address = (c[4] << 8) | (c[5]);  // 字节4-5: 目标地址
uint8_t len = c[6] + 1;                         // 字节6: 数据长度
l->lsdu.set(c.data() + 7, len);                 // 字节7开始: LSDU数据
```

### 7.4 优先级定义
```cpp
// lpdu.h:35-41
enum EIB_Priority : uint8_t {
  PRIO_SYSTEM = 0,    // 00: 系统优先级 (最高)
  PRIO_NORMAL = 1,    // 01: 普通优先级
  PRIO_URGENT = 2,    // 10: 紧急优先级
  PRIO_LOW = 3        // 11: 低优先级 (最低)
}
```

### 7.5 控制字段构造
```cpp
// cm_tp1.cpp:95,109
// 标准帧:
pdu[0] = 0x90 | (p->repeated ? 0x00 : 0x20) | (p->priority << 2);
// 扩展帧:
pdu[0] = 0x10 | (p->repeated ? 0x00 : 0x20) | (p->priority << 2);
```

### 7.6 长度计算和编码
```cpp
// 发送帧时的长度编码 (cm_tp1.cpp:90-103)
uint8_t len = p->lsdu.size() - 1;  // 计算编码值: LSDU长度-1
if (len <= 0x0f) {                 // 检查是否可用标准帧 (≤15即LSDU≤16字节)
  // 标准帧: 长度编码到NPDU头的低4位
  pdu[5] = (p->address_type == GroupAddress ? 0x80 : 0x00) |
           ((p->hop_count & 0x07) << 4) |
           (len & 0x0f);           // 长度字段: LSDU长度-1 (0-15)
} else {
  // 扩展帧: 专用长度字节
  pdu[6] = (p->lsdu.size() - 1) & 0xff;  // 长度字段: LSDU长度-1 (0-255)
}

// 接收帧时的长度解码 (cm_tp1.cpp:42,57)
// 标准帧:
uint8_t len = (c[5] & 0x0f) + 1;   // 从NPDU头恢复: 字段值+1 = 真实LSDU长度
// 扩展帧:
uint8_t len = c[6] + 1;            // 从长度字节恢复: 字段值+1 = 真实LSDU长度

// 总帧长度计算 (tpuart.cpp:408-409)
unsigned len = ext ? in[6] : (in[5] & 0x0f);  // 获取编码后的长度值 (LSDU长度-1)
len += 6 + ext + 2;  // 总长度 = (LSDU长度-1) + 头部长度 + 校验和长度
                     // 标准帧: (LSDU-1) + 6 + 0 + 2 = LSDU + 7
                     // 扩展帧: (LSDU-1) + 6 + 1 + 2 = LSDU + 8
```

### 7.7 TPCI解析
```cpp
// tpdu.cpp:31-49
if (address_type == GroupAddress) {
  if ((c[0] & 0xFC) == 0x00)      // 00xxxxxx: T_Data_Group
    t = TPDUPtr(new T_Data_Group_PDU());
  else if ((c[0] & 0xFC) == 0x04) // 01xxxxxx: T_Data_Tag_Group
    t = TPDUPtr(new T_Data_Tag_Group_PDU());
}
```

### 7.8 APCI解析
```cpp
// apdu.cpp:38-39
uint16_t apci = ((c[0] & 0x03) << 8) | c[1];  // 组合10位APCI
switch (apci) {
  case 0x000: A_GroupValue_Read         // 读组值
  case 0x040: A_GroupValue_Response     // 组值响应
  case 0x080: A_GroupValue_Write        // 写组值
  // ...
}
```

### 7.9 数据存储格式处理
```cpp
// A_GroupValue_Write_PDU::init() - 数据格式自动识别
bool A_GroupValue_Write_PDU::init (const CArray & c, TracePtr)
{
  if (c.size() < 2)
    return false;

  issmall = (c.size() == 2);        // 判断数据格式
  if (issmall)
    {
      // 6位数据格式: 数据嵌入在APCI字段中
      data.resize(1);
      data[0] = c[1] & 0x3f;         // 提取低6位数据 (0-63)
    }
  else
    {
      // 多字节数据格式: 数据从字节2开始独立存储
      data.set (c.data() + 2, c.size() - 2);
    }
  return true;
}

// A_GroupValue_Write_PDU::ToPacket() - 数据编码
CArray A_GroupValue_Write_PDU::ToPacket () const
{
  CArray pdu;
  pdu.resize (2);
  pdu[0] = A_GroupValue_Write >> 8;           // APCI高字节
  pdu[1] = A_GroupValue_Write & 0xc0;         // APCI低字节(高2位)
  
  if (issmall)
    {
      // 6位数据: 编码到APCI的低6位
      pdu[1] |= data[0] & 0x3F;              // 数据值(0-63)
    }
  else
    {
      // 多字节数据: 扩展APDU长度并附加数据
      pdu.resize (2 + data.size());
      pdu.setpart (data.data(), 2, data.size());  // 从字节2开始存储数据
    }
  return pdu;
}
```

### 7.10 控制字段验证
```cpp
// cm_tp1.cpp:29
if ((c[0] & 0x53) != 0x10)  // 0x53 = 01010011, 0x10 = 00010000
  return nullptr;  // 验证失败
```
