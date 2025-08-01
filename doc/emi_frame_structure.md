# KNX EMI帧结构分析

> 本文档基于KNXD源代码深入分析KNX EMI (External Message Interface) 帧的结构和解析逻辑

## 目录

1. [概述](#概述)
2. [EMI1/EMI2帧结构](#1-emi1emi2帧结构)
3. [CEMI帧结构](#2-cemi帧结构)
4. [帧格式对比](#3-帧格式对比)
5. [消息类型与服务](#4-消息类型与服务)
6. [地址编码机制](#5-地址编码机制)
7. [长度字段处理](#6-长度字段处理)
8. [确认机制](#7-确认机制)
9. [代码参考](#8-代码参考)

## 概述

KNX EMI (External Message Interface) 是KNX设备与主机系统之间的标准通信接口。KNXD支持三种EMI版本：

- **EMI1**: 传统EMI接口，主要用于串口通信
- **EMI2**: EMI1的增强版本，增加了更多功能
- **CEMI**: Common EMI，现代化接口，主要用于USB和IP通信

**接口特征**：
- **EMI1/EMI2**: 简化的二进制协议，帧长度较短
- **CEMI**: 功能丰富的协议，支持扩展信息和属性操作
- **转换机制**: KNXD内部统一使用LPDU格式，通过转换函数实现与各EMI版本的互操作

**文档覆盖范围**：
- EMI1/EMI2帧结构和编码方式
- CEMI帧结构和扩展特性
- 内部数据转换机制和代码实现

---

## 1. EMI1/EMI2帧结构

### 1.1 帧格式

EMI1和EMI2使用相同的基础帧结构，与TP1帧格式类似：

```
总长度: 1字节消息码 + 6字节头部 + LSDU长度 (最大23字节)

偏移  字段名             长度    说明
0     消息码 (MC)        1字节   EMI消息类型
1     控制字段           1字节   帧控制信息
2-3   源地址             2字节   发送设备地址
4-5   目标地址           2字节   接收设备地址
6     NPDU头             1字节   地址类型+跳数+长度
7-N   LSDU数据           0-15字节 传输层+应用层数据
```

### 1.2 字段详解

#### 消息码 (字节0) - Message Code
```
EMI1常用消息码:
0x11: L_Data.req      (数据发送请求)
0x2E: L_Data.con      (数据发送确认)  
0x29: L_Data.ind      (数据接收指示)
0x49: L_Busmon.ind    (总线监控指示)
0x46: Local服务消息   (本地设备控制)
```

#### 控制字段 (字节1) - 类似TP1格式
```
Bit 7-6  [11] 帧类型:     固定为11 (标准帧)
Bit 5    [R] 重复标志:    0=重复帧, 1=非重复帧
Bit 4    [1] 标准位:      固定为1
Bit 3-2  [PP] 优先级:     00=系统, 01=普通, 10=紧急, 11=低
Bit 1-0  [00] 保留:       固定为00
```

**EMI控制字段编码**:
```c
// emi.cpp:136-137
pdu[1] = 0xBC | (l1->repeated ? 0x00 : 0x20) | (l1->priority << 2);
// 0xBC = 10111100₂ = 帧类型11 + 标准位1 + 重复位1 + 保留00
```

#### 地址字段 (字节2-5) - 与TP1相同
- **源地址** (字节2-3): 个体地址，格式为 区域.线路.设备
- **目标地址** (字节4-5): 个体地址或组地址，根据AT位确定

#### NPDU头 (字节6) - 与TP1相同
```
Bit 7     [G] 地址类型:    1=组地址, 0=个体地址
Bit 6-4   [HHH] 跳数:     网络跳数计数器 (0-7)
Bit 3-0   [LLLL] 长度:    LSDU长度-1 (0-15)
```

#### LSDU数据 (字节7-N) - 链路服务数据单元
LSDU (Link Service Data Unit) 在EMI帧中的结构与TP1帧完全相同，包含传输层和应用层数据：

**LSDU层次结构**:
```
LSDU = TPDU = TPCI + APDU + [数据]
             (1字节) (1-2字节) (0-N字节)
             
总最小长度: 2字节 (TPCI + APCI)
```

**数据存储格式**: EMI支持与TP1相同的两种数据格式

##### 6位数据格式 (≤6位数据)
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

##### 多字节数据格式 (>6位数据)  
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

**TPCI (传输层协议控制信息)**:
```
字节0的高6位定义传输服务类型:
- 00xxxxxx: T_Data_Group (组数据传输)
- 01xxxxxx: T_Data_Tag_Group (带标签的组数据)  
- 10xxxxxx: T_Data_Individual (个体数据传输)
- 11xxxxxx: T_Data_Connected (连接型数据传输)
```

**APCI (应用层协议控制信息)**:
```
10位APCI编码跨越2字节:
- APCI高2位: 字节0的低2位 (Bit 1-0)
- APCI低8位: 字节1 (可能包含6位数据)
- 完整APCI = (字节0 & 0x03) << 8 | (字节1 & 0xC0)

常见APCI值:
- 0x000: A_GroupValue_Read (组值读取)
- 0x040: A_GroupValue_Response (组值响应)
- 0x080: A_GroupValue_Write (组值写入)
```

**LSDU长度验证与边界条件**:
```c
// apdu.cpp:384-402 - 6位vs多字节数据判断
bool A_GroupValue_Write_PDU::init (const CArray & c, TracePtr)
{
  if (c.size() < 2)
    return false;

  issmall = (c.size() == 2);  // 2字节=6位数据,>2字节=多字节数据
  if (issmall)
    {
      data.resize(1);
      data[0] = c[1] & 0x3f;   // 提取低6位数据
    }
  else
    {
      data.set (c.data() + 2, c.size() - 2); // 从字节2开始提取数据
    }
  return true;
}
```

**EMI1/EMI2 LSDU长度限制**:
- **最小长度**: 2字节 (TPCI + APCI，无数据)
- **最大长度**: 16字节 (4位长度字段: 0x0-0xF = 1-16字节)
- **数据容量**: 0-14字节应用数据 (16字节总长度减去2字节TPCI+APCI)
- **格式选择**: 由APDU解析器根据总长度自动判断6位或多字节格式

**编码一致性保证**:
```c
// emi.cpp:26-27 - LSDU基本验证
assert (l1->lsdu.size() >= 1);   // 至少包含TPCI
assert (l1->lsdu.size() < 0xff); // EMI最大支持255字节
```

### 1.3 EMI帧格式选择

EMI1/EMI2不支持扩展帧，仅使用标准帧格式：

```c
// emi.cpp:129-153
CArray L_Data_ToEMI (uint8_t code, const LDataPtr & l1)
{
  CArray pdu;
  uint8_t len = l1->lsdu.size() - 1;
  
  pdu[0] = code;  // EMI消息码
  
  // EMI仅支持标准帧格式
  if (len <= 0x0f)
    {
      pdu.resize (l1->lsdu.size() + 7);
      pdu[1] = 0xBC | (l1->repeated ? 0x00 : 0x20) | (l1->priority << 2);
      // 地址和LSDU数据处理与TP1相同
      pdu[2] = (l1->source_address >> 8) & 0xff;
      pdu[3] = (l1->source_address) & 0xff;
      pdu[4] = (l1->destination_address >> 8) & 0xff;
      pdu[5] = (l1->destination_address) & 0xff;
      pdu[6] = (l1->address_type == GroupAddress ? 0x80 : 0x00) |
               ((l1->hop_count & 0x07) << 4) |
               (len & 0x0f);
      pdu.setpart (l1->lsdu.data(), 7, l1->lsdu.size());
    }
}
```

### 1.4 EMI示例帧分析

#### 示例1: L_Data.req (0x11) - 数据发送请求
```
11 BC 11 01 02 03 8F 81 0F
```

**字段解析**:
- `11`: L_Data.req (数据发送请求)
- `BC`: 标准帧(11) + 非重复(1) + 标准位(1) + 普通优先级(01) + 保留(00)
- `11 01`: 源地址 = 1.1.1
- `02 03`: 目标地址 = 0x0203
- `8F`: 组地址(1) + 跳数0(000) + LSDU长度2字节(1111)
- `81 0F`: LSDU数据 (A_GroupValue_Write + 6位数据值15)
  - `81`: TPCI=00(T_Data_Group) + APCI高2位=10, APCI低8位=000001(含6位数据)
  - 完整APCI=0x080 (A_GroupValue_Write)
  - 6位数据值=0x0F (存储在APCI字节的低6位)
  - `0F`: APCI中4位=0001 + 6位数据=1111 (值15)
  - 完整APCI=0x080 (A_GroupValue_Write)
  - 数据值=15 (存储在APCI低6位)

#### 示例2: L_Data.req (0x11) - 多字节数据
```
11 BC 11 01 02 03 91 80 12 34
```

**字段解析**:
- `11`: L_Data.req (数据发送请求)
- `BC`: 标准帧 + 非重复 + 普通优先级
- `11 01`: 源地址 = 1.1.1
- `02 03`: 目标地址 = 0x0203
- `91`: 组地址(1) + 跳数0(000) + LSDU长度4字节(0001)
- `80 12 34`: LSDU数据 (A_GroupValue_Write + 2字节数据)
  - `80`: TPCI=00(T_Data_Group) + APCI高2位=10, APCI低8位=00000000
  - 完整APCI=0x080 (A_GroupValue_Write)
  - `12 34`: 2字节独立数据=0x1234 (多字节格式，从字节2开始存储)

#### 示例3: L_Data.con (0x2E) - 数据发送确认
```
2E
```
**说明**: 确认帧通常只包含消息码，表示前一个发送请求已处理

#### 示例4: L_Busmon.ind (0x49) - 总线监控
```
49 00 12 34 BC 11 01 02 03 8F 81 0F
```

**字段解析**:
- `49`: L_Busmon.ind (总线监控指示)
- `00`: 状态字节
- `12 34`: 时间戳 (16位)
- `BC...0F`: 原始TP1帧数据

---

## 2. CEMI帧结构

### 2.1 帧格式

CEMI使用更复杂的帧结构，支持扩展信息：

```
总长度: 1字节消息码 + 1字节附加信息长度 + 可变附加信息 + 6字节cEMI头 + LSDU长度

偏移  字段名                 长度      说明
0     消息码 (MC)            1字节     CEMI消息类型
1     附加信息长度 (AddIL)   1字节     附加信息字节数
2-N   附加信息 (AddInfo)     0-N字节   可选的扩展信息
N+1   控制字段1              1字节     cEMI控制信息1
N+2   控制字段2              1字节     cEMI控制信息2  
N+3-4 源地址                 2字节     发送设备地址
N+5-6 目标地址               2字节     接收设备地址
N+7   LSDU长度               1字节     LSDU字节数
N+8-M LSDU数据               0-255字节 传输层+应用层数据
```

### 2.2 字段详解

#### CEMI消息码 (字节0)
```
常用CEMI消息码:
0x11: L_Data.req        (数据发送请求)
0x2E: L_Data.con        (数据发送确认)
0x29: L_Data.ind        (数据接收指示)  
0x2B: L_Busmon.ind      (总线监控指示)
0xF6: M_PropWrite.req   (属性写请求)
0xF5: M_PropRead.req    (属性读请求)
0xF7: M_PropRead.con    (属性读确认)
```

#### 附加信息 (AddInfo)
附加信息是CEMI的扩展特性，用于携带额外的元数据：

```c
// emi.cpp:105-108 - CEMI附加信息类型
enum {
  CEMI_ADD_HEADER_TYPE_STATUS = 0x03,     // 状态信息
  CEMI_ADD_HEADER_TYPE_TIMESTAMP = 0x04,  // 时间戳  
  CEMI_ADD_HEADER_TYPE_EXTTIMESTAMP = 0x06, // 扩展时间戳
};
```

**附加信息格式**:
```
每个附加信息块:
  字节0: Type ID (信息类型)
  字节1: Length (数据长度)
  字节2-N: Data (具体数据)
```

#### CEMI控制字段
**控制字段1** (字节N+1):
```
Bit 7    [F] 帧格式:      0=扩展帧, 1=标准帧
Bit 6    [R] 保留:        固定为0
Bit 5    [R] 重复标志:    0=重复帧, 1=非重复帧  
Bit 4    [S] 系统广播:    系统消息标志
Bit 3-2  [PP] 优先级:     00=系统, 01=普通, 10=紧急, 11=低
Bit 1    [A] 确认请求:    是否需要确认
Bit 0    [C] 确认:        确认位
```

**控制字段2** (字节N+2):
```
Bit 7     [G] 地址类型:    1=组地址, 0=个体地址
Bit 6-4   [HHH] 跳数:     网络跳数计数器 (0-7)
Bit 3-0   [0000] 扩展:    扩展帧中固定为0000
```

#### LSDU数据 (字节N+8-M) - 链路服务数据单元
CEMI中的LSDU结构与EMI1/EMI2相同，但长度限制更宽松：

**LSDU层次结构**: 与EMI1/EMI2完全相同
```
LSDU = TPDU = TPCI + APDU + [数据]
             (1字节) (1-2字节) (0-N字节)
```

**长度差异**:
- **EMI1/EMI2**: 最大16字节LSDU (4位长度字段)
- **CEMI**: 最大256字节LSDU (8位专用长度字段)

**数据格式**: 支持与TP1相同的6位数据和多字节数据格式

**TPCI/APCI编码**: 与EMI1/EMI2和TP1完全相同，确保协议兼容性

**CEMI LSDU长度处理**:
```c
// emi.cpp:26-27,45-46 - CEMI长度编码
assert (l1->lsdu.size() >= 1);     // 最小1字节(仅TPCI)
assert (l1->lsdu.size() < 0xff);   // 最大255字节
...
pdu[8] = l1->lsdu.size() - 1;      // 专用8位长度字段
pdu.setpart (l1->lsdu.data(), 9, l1->lsdu.size()); // 数据复制

// emi.cpp:73 - CEMI长度解析
c->lsdu.set (data.data() + start + 7, data[6 + start] + 1);
// 从专用长度字段读取: 实际长度 = 字段值 + 1
```

**CEMI扩展特性对LSDU的影响**:
- **理论容量**: 最大256字节LSDU数据
- **实际配置**: KNXD限制为50字节 (考虑性能和兼容性)
- **附加信息**: 不影响LSDU结构，独立于LSDU处理
- **扩展帧**: 支持更大数据包，但LSDU内部格式保持不变
````
### 2.3 CEMI编码实现

```c
// emi.cpp:23-40 - CEMI帧构造
CArray L_Data_ToCEMI (uint8_t code, const LDataPtr & l1)
{
  CArray pdu;
  assert (l1->lsdu.size() >= 1);
  assert (l1->lsdu.size() < 0xff);
  assert ((l1->hop_count & 0xf8) == 0);

  pdu.resize (l1->lsdu.size() + 9);
  pdu[0] = code;                                    // 消息码
  pdu[1] = 0x00;                                   // 附加信息长度=0
  pdu[2] = 0x10 | (l1->priority << 2) |            // 控制字段1
           (l1->lsdu.size() - 1 <= 0x0f ? 0x80 : 0x00);
  if (code == 0x29)                                // L_Data.ind处理重复标志
    pdu[2] |= (l1->repeated ? 0 : 0x20);
  else
    pdu[2] |= 0x20;
  pdu[3] = (l1->address_type == GroupAddress ? 0x80 : 0x00) |  // 控制字段2
           ((l1->hop_count & 0x7) << 4) | 0x0;
  pdu[4] = (l1->source_address >> 8) & 0xff;       // 源地址
  pdu[5] = (l1->source_address) & 0xff;
  pdu[6] = (l1->destination_address >> 8) & 0xff;  // 目标地址
  pdu[7] = (l1->destination_address) & 0xff;
  pdu[8] = l1->lsdu.size() - 1;                    // LSDU长度
  pdu.setpart (l1->lsdu.data(), 9, l1->lsdu.size()); // LSDU数据
  return pdu;
}
```

### 2.4 CEMI示例帧分析

#### 示例1: L_Data.req (0x11) - 带附加信息
```
11 00 10 80 11 01 02 03 01 81 0F
```

**字段解析**:
- `11`: L_Data.req
- `00`: 附加信息长度=0
- `10`: 控制字段1 = 标准帧(1) + 保留(0) + 非重复(1) + 系统(0) + 普通优先级(00) + 确认(0) + 确认位(0)
- `80`: 控制字段2 = 组地址(1) + 跳数0(000) + 扩展位(0000)
- `11 01`: 源地址 = 1.1.1
- `02 03`: 目标地址 = 0x0203
- `01`: LSDU长度 = 2字节
- `81 0F`: LSDU数据 (A_GroupValue_Write + 6位数据值15)
  - `81`: TPCI=00(T_Data_Group) + APCI高2位=10, APCI低8位=000001(含6位数据)
  - 完整APCI=0x080 (A_GroupValue_Write)  
  - 6位数据值=0x0F (存储在APCI字节的低6位)

#### 示例2: L_Data.req (0x11) - CEMI多字节数据
```
11 00 10 80 11 01 02 03 03 80 12 34
```

**字段解析**:
- `11`: L_Data.req
- `00`: 附加信息长度=0
- `10`: 控制字段1 = 标准帧(1) + 非重复(1) + 普通优先级(00)
- `80`: 控制字段2 = 组地址(1) + 跳数0(000)
- `11 01`: 源地址 = 1.1.1
- `02 03`: 目标地址 = 0x0203
- `03`: LSDU长度 = 4字节  
- `80 12 34`: LSDU数据 (A_GroupValue_Write + 2字节数据)
  - `80`: TPCI=00(T_Data_Group) + APCI高2位=10, APCI低8位=00000000
  - 完整APCI=0x080 (A_GroupValue_Write)
  - `12 34`: 2字节独立数据=0x1234 (多字节格式，从字节2开始存储)

#### 示例3: L_Busmon.ind (0x2B) - 带时间戳
```
2B 07 03 01 00 04 02 12 34 BC 11 01 02 03 8F 81 0F
```

**字段解析**:
- `2B`: L_Busmon.ind  
- `07`: 附加信息长度=7字节
- `03 01 00`: 状态信息 (Type=03, Len=01, Data=00)
- `04 02 12 34`: 时间戳 (Type=04, Len=02, Data=1234)
- `BC...0F`: 原始TP1帧数据

---

## 3. 帧格式对比

### 3.1 结构差异

| 特性           | EMI1/EMI2        | CEMI            |
|----------------|------------------|-----------------|
| 消息码位置     | 字节0            | 字节0           |
| 附加信息       | 不支持           | 支持可变长度    |
| 控制字段       | 1字节            | 2字节           |
| 最大LSDU长度   | 16字节           | 255字节         |
| 扩展帧支持     | 否               | 是              |
| 属性操作       | 有限             | 完整支持        |

### 3.2 消息码映射

```c
// EMI1消息码
static const uint8_t emi1_indTypes[] = { 0x2E, 0x29, 0x49 };

// CEMI消息码  
static const uint8_t cemi_indTypes[] = { 0x2E, 0x29, 0x2B };

// 对应关系:
// [0] = 确认消息: EMI1/CEMI都是0x2E
// [1] = 数据指示: EMI1/CEMI都是0x29  
// [2] = 监控指示: EMI1=0x49, CEMI=0x2B
```

### 3.3 长度处理差异

```c
// EMI1/EMI2: 最大16字节LSDU
virtual unsigned int maxPacketLen() const
{
  return 0x10;  // EMI1/EMI2限制
}

// CEMI: 最大255字节LSDU  
unsigned int CEMIDriver::maxPacketLen() const
{
  return 50;    // 实际配置为50字节
}
```

---

## 4. 消息类型与服务

### 4.1 数据传输服务

#### L_Data服务 - 数据链路层数据传输
```
L_Data.req (0x11): 数据发送请求
  - 应用层 → EMI → 设备
  - 用于发送KNX报文到总线

L_Data.ind (0x29): 数据接收指示  
  - 设备 → EMI → 应用层
  - 从总线接收到的KNX报文

L_Data.con (0x2E): 数据发送确认
  - 设备 → EMI → 应用层  
  - 确认L_Data.req已处理
```

#### L_Busmon服务 - 总线监控
```
L_Busmon.ind (EMI1: 0x49, CEMI: 0x2B): 总线监控指示
  - 设备 → EMI → 应用层
  - 提供原始总线数据用于监控和分析
```

### 4.2 本地服务 (仅EMI1/EMI2)

#### 设备管理服务
```c
// emi1.cpp:35-37 - 进入监控模式
const uint8_t t[] = { 0x46, 0x01, 0x00, 0x60, 0x90 };

// emi1.cpp:58-59 - 退出监控模式  
uint8_t t[] = { 0x46, 0x01, 0x00, 0x60, 0xc0 };

// emi1.cpp:65-66 - 清除地址表
const uint8_t ta[] = { 0x46, 0x01, 0x01, 0x16, 0x00 };
```

### 4.3 属性服务 (仅CEMI)

#### M_PropWrite/M_PropRead - 对象属性操作
```c
// cemi.cpp:87-96 - 设置通信模式
CArray set_comm_mode;
set_comm_mode[0] = 0xf6;  // M_PropWrite.req
set_comm_mode[1] = 0x00;  // Interface Object Type High
set_comm_mode[2] = 0x08;  // Interface Object Type Low  
set_comm_mode[3] = 0x01;  // Object Instance
set_comm_mode[4] = 0x34;  // Property ID (PID_COMM_MODE)
set_comm_mode[5] = 0x10;  // NoE + Start Index High
set_comm_mode[6] = 0x01;  // Start Index Low
set_comm_mode[7] = 0x00;  // Data (Data Link Layer mode)
```

---

## 5. 地址编码机制

EMI接口中的地址编码与TP1完全相同，通过统一的LPDU转换实现：

### 5.1 地址类型识别
```c
// CEMI地址类型检查 (emi.cpp:65)
c->address_type = (data[start + 1] & 0x80) ? GroupAddress : IndividualAddress;

// EMI1/EMI2地址类型检查 (emi.cpp:178)  
c->address_type = (data[6] & 0x80) ? GroupAddress : IndividualAddress;
```

### 5.2 地址提取
```c
// CEMI地址提取 (emi.cpp:58-60)
c->source_address = (data[start + 2] << 8) | (data[start + 3]);
c->destination_address = (data[start + 4] << 8) | (data[start + 5]);

// EMI1/EMI2地址提取 (emi.cpp:173-174)
c->source_address = (data[2] << 8) | (data[3]);
c->destination_address = (data[4] << 8) | (data[5]);
```

### 5.3 地址编码
地址编码复用TP1的实现逻辑：
- **个体地址**: 区域.线路.设备 格式，4+4+8位编码
- **组地址**: 主组/中组/子组 格式，5+3+8位编码

---

## 6. 长度字段处理

### 6.1 EMI1/EMI2长度处理
```c
// emi.cpp:176-179 - EMI长度解析
c->address_type = (data[6] & 0x80) ? GroupAddress : IndividualAddress;
len = (data[6] & 0x0f) + 1;  // 4位长度字段，最大16字节
if (len > data.size() - 7)
  len = data.size() - 7;
c->lsdu.set (data.data() + 7, len);
```

**特点**:
- 4位长度字段，范围0-15
- 实际LSDU长度 = 字段值 + 1
- 最大支持16字节LSDU

**LSDU长度约束**:
- **最小长度**: 2字节 (TPCI + APCI，与TP1相同)
- **实际范围**: 2-16字节 (字段值1-15)
- **数据容量**: 0-14字节应用数据 (16字节总长度减去2字节TPCI+APCI)
- **格式选择**: 由APDU解析器根据总长度自动判断6位或多字节格式

### 6.2 CEMI长度处理
```c
// emi.cpp:61-62 - CEMI长度解析
c->lsdu.set (data.data() + start + 7, data[6 + start] + 1);
// 8位专用长度字段，最大256字节
```

**特点**:
- 8位专用长度字段，范围0-255
- 实际LSDU长度 = 字段值 + 1  
- 最大支持256字节LSDU

---

## 7. 确认机制

### 7.1 EMI确认流程

EMI接口使用异步确认机制确保数据传输可靠性：

```c
// emi_common.cpp:105-125 - 发送流程
void EMI_Common::send_L_Data (LDataPtr l)
{
  if (state != E_idle) {
    ERRORPRINTF(t, E_ERROR | 59, "EMI_common: send while waiting (%d)", state);
    return;
  }
  
  CArray pdu = lData2EMI (0x11, l);  // 构造L_Data.req
  out = pdu;
  retries = 0;
  send_Data (pdu);
}

void EMI_Common::send_Data(CArray &pdu)
{
  state = E_wait;              // 等待do_send_Next
  timeout.start(send_timeout,0);
  iface->send_Data(pdu);
}
```

### 7.2 状态机管理
```c
// emi_common.h:54-61 - EMI状态定义
enum E_state
{
  E_idle,           // 空闲状态
  E_timed_out,      // 超时但仍等待sendNext
  E_wait,           // 等待sendNext和confirm
  E_wait_confirm,   // sendNext已到达但未收到确认
};
```

### 7.3 超时和重试机制
```c
// emi_common.cpp:144-162 - 超时处理
void EMI_Common::timeout_cb(ev::timer &, int)
{
  if (state <= E_timed_out)
    return;
  if (state == E_wait) {
    state = E_timed_out;
    stop(true);
    return;
  }
  assert (state == E_wait_confirm);
  if (++retries <= max_retries) {
    TRACEPRINTF (t, 1, "No confirm, repeating");
    send_Data(out);  // 重发数据包
    return;
  }
  
  ERRORPRINTF(t, E_WARNING | 119, "EMI: No confirm, packet discarded");
  state = E_idle;
  LowLevelFilter::do_send_Next();
}
```

### 7.4 确认消息处理
```c
// emi_common.cpp:167-184 - 接收处理
void EMI_Common::recv_Data(CArray& c)
{
  const uint8_t *ind = getIndTypes();
  if (c.size() > 0 && c[0] == ind[I_CONFIRM]) {  // 0x2E确认消息
    if (state == E_wait_confirm) {
      TRACEPRINTF (t, 2, "Confirmed");
      state = E_idle;
      timeout.stop();
      LowLevelFilter::do_send_Next();
    }
    else
      TRACEPRINTF (t, 2, "spurious Confirm %d",(int)state);
  }
}
```

---

## 8. 代码参考

以下代码引用来自KNXD项目，展示了EMI接口的实际实现：

### 8.1 EMI版本检测和初始化
```cpp
// emi_common.cpp:27-47 - EMI版本配置
EMIVer cfgEMIVersion(IniSectionPtr& s)
{
  int v = s->value("version",vERROR);
  if (v > vRaw || v < vERROR)
    return vERROR;
  else if (v != vERROR)
    return EMIVer(v);

  std::string sv = s->value("version","");
  if (!sv.size())
    return vUnknown;
  else if (sv == "EMI1")
    return vEMI1;
  else if (sv == "EMI2")
    return vEMI2;
  else if (sv == "CEMI")
    return vCEMI;
  else if (sv == "raw")
    return vRaw;
  else
    return vERROR;
}
```

### 8.2 LPDU到EMI转换
```cpp
// emi.cpp:129-153 - EMI1/EMI2帧构造
CArray L_Data_ToEMI (uint8_t code, const LDataPtr & l1)
{
  CArray pdu;
  uint8_t len = l1->lsdu.size() - 1;
  
  pdu[0] = code;
  
  if (len <= 0x0f)
    {
      // EMI标准帧格式
      pdu.resize (l1->lsdu.size() + 7);
      pdu[1] = 0xBC | (l1->repeated ? 0x00 : 0x20) | (l1->priority << 2);
      pdu[2] = (l1->source_address >> 8) & 0xff;
      pdu[3] = (l1->source_address) & 0xff;
      pdu[4] = (l1->destination_address >> 8) & 0xff;
      pdu[5] = (l1->destination_address) & 0xff;
      pdu[6] = (l1->address_type == GroupAddress ? 0x80 : 0x00) |
               ((l1->hop_count & 0x07) << 4) |
               (len & 0x0f);
      pdu.setpart (l1->lsdu.data(), 7, l1->lsdu.size());
    }
  
  return pdu;
}
```

### 8.3 EMI到LPDU转换
```cpp
// emi.cpp:164-184 - EMI1/EMI2帧解析
LDataPtr EMI_to_L_Data (const CArray & data, TracePtr)
{
  LDataPtr c = LDataPtr(new L_Data_PDU ());
  unsigned len;

  if (data.size() < 8)
    return 0;

  c->source_address = (data[2] << 8) | (data[3]);
  c->destination_address = (data[4] << 8) | (data[5]);
  c->address_type = (data[6] & 0x80) ? GroupAddress : IndividualAddress;
  len = (data[6] & 0x0f) + 1;
  if (len > data.size() - 7)
    len = data.size() - 7;
  c->lsdu.set (data.data() + 7, len);
  c->hop_count = (data[6] >> 4) & 0x07;
  return c;
}
```

### 8.4 CEMI帧构造
```cpp
// emi.cpp:23-40 - CEMI帧构造  
CArray L_Data_ToCEMI (uint8_t code, const LDataPtr & l1)
{
  CArray pdu;
  assert (l1->lsdu.size() >= 1);
  assert (l1->lsdu.size() < 0xff);
  assert ((l1->hop_count & 0xf8) == 0);

  pdu.resize (l1->lsdu.size() + 9);
  pdu[0] = code;
  pdu[1] = 0x00;                                   // AddIL = 0
  pdu[2] = 0x10 | (l1->priority << 2) |            // 控制字段1
           (l1->lsdu.size() - 1 <= 0x0f ? 0x80 : 0x00);
  if (code == 0x29)
    pdu[2] |= (l1->repeated ? 0 : 0x20);
  else
    pdu[2] |= 0x20;
  pdu[3] = (l1->address_type == GroupAddress ? 0x80 : 0x00) |  // 控制字段2
           ((l1->hop_count & 0x7) << 4) | 0x0;
  pdu[4] = (l1->source_address >> 8) & 0xff;
  pdu[5] = (l1->source_address) & 0xff;
  pdu[6] = (l1->destination_address >> 8) & 0xff;
  pdu[7] = (l1->destination_address) & 0xff;
  pdu[8] = l1->lsdu.size() - 1;
  pdu.setpart (l1->lsdu.data(), 9, l1->lsdu.size());
  return pdu;
}
```

### 8.5 CEMI帧解析
```cpp
// emi.cpp:42-74 - CEMI帧解析
LDataPtr CEMI_to_L_Data (const CArray & data, TracePtr tr)
{
  if (data.size() < 2) {
    TRACEPRINTF (tr, 7, "packet too short (%d)", data.size());
    return nullptr;
  }
  unsigned start = data[1] + 2;  // 跳过附加信息
  if (data.size() < 7 + start) {
    TRACEPRINTF (tr, 7, "start too large (%d/%d)", data.size(),start);
    return nullptr;
  }
  if (data.size() < 7 + start + data[6 + start] + 1) {
    TRACEPRINTF (tr, 7, "packet too short (%d/%d)", 
                 data.size(), 7 + start + data[6 + start] + 1);
    return nullptr;
  }

  LDataPtr c = LDataPtr(new L_Data_PDU ());
  c->source_address = (data[start + 2] << 8) | (data[start + 3]);
  c->destination_address = (data[start + 4] << 8) | (data[start + 5]);
  c->lsdu.set (data.data() + start + 7, data[6 + start] + 1);
  if (data[0] == 0x29)
    c->repeated = (data[start] & 0x20) ? 0 : 1;
  else
    c->repeated = 0;
  c->priority = static_cast<EIB_Priority>((data[start] >> 2) & 0x3);
  c->hop_count = (data[start + 1] >> 4) & 0x07;
  c->address_type = (data[start + 1] & 0x80) ? GroupAddress : IndividualAddress;
  return c;
}
```

### 8.6 EMI1设备控制指令
```cpp
// emi1.cpp:33-37 - 进入监控模式
void EMI1Driver::cmdEnterMonitor()
{
  sendLocal_done_next = N_up;
  const uint8_t t[] = { 0x46, 0x01, 0x00, 0x60, 0x90 };
  send_Local (CArray (t, sizeof (t)), 1);
}

// emi1.cpp:56-60 - 退出监控模式
void EMI1Driver::cmdLeaveMonitor()
{
  sendLocal_done_next = N_down;
  uint8_t t[] = { 0x46, 0x01, 0x00, 0x60, 0xc0 };
  send_Local (CArray (t, sizeof (t)),1);
}

// emi1.cpp:63-67 - 打开链路层
void EMI1Driver::cmdOpen ()
{
  sendLocal_done_next = N_open;
  const uint8_t ta[] = { 0x46, 0x01, 0x01, 0x16, 0x00 }; // 清除地址表
  send_Local (CArray (ta, sizeof (ta)),1);
}
```

### 8.7 CEMI属性操作
```cpp
// cemi.cpp:85-99 - 设置通信模式
void CEMIDriver::do_send_Next()
{
  if (after_reset) {
    if (!sent_comm_mode) {
      sent_comm_mode = true;
      
      // 设置通信模式为"数据链路层"(0x00)
      CArray set_comm_mode;
      set_comm_mode.resize (8);
      set_comm_mode[0] = 0xf6; // M_PropWrite.req
      set_comm_mode[1] = 0x00; // Interface Object Type High
      set_comm_mode[2] = 0x08; // Interface Object Type Low (cEMI Server Object)
      set_comm_mode[3] = 0x01; // Object Instance
      set_comm_mode[4] = 0x34; // Property ID (PID_COMM_MODE)
      set_comm_mode[5] = 0x10; // NoE=1, Start Index High=0
      set_comm_mode[6] = 0x01; // Start Index Low=1
      set_comm_mode[7] = 0x00; // Data (0x00 = "Data Link Layer")
      send_Data (set_comm_mode);
    }
  }
}
```

### 8.8 EMI消息类型常量
```cpp
// emi1.cpp:100-104 - EMI1消息类型
const uint8_t * EMI1Driver::getIndTypes() const
{
  static const uint8_t indTypes[] = { 0x2E, 0x29, 0x49 };
  //                                  确认  数据  监控
  return indTypes;
}

// cemi.cpp:122-126 - CEMI消息类型  
const uint8_t * CEMIDriver::getIndTypes() const
{
  static const uint8_t indTypes[] = { 0x2E, 0x29, 0x2B };
  //                                  确认  数据  监控
  return indTypes;
}
```
