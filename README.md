# QoS课程论文实验项目说明

本项目对应论文《QoS课程论文_三平台实验与WRR权重优化》相关的实验素材、仿真文件、抓包数据和 MATLAB 建模代码。

## 项目内容

- `Matlab源代码文件/`
  - `qos_matlab_simulation.m`：MATLAB 队列调度仿真主脚本
  - `figures/`：脚本生成的结果图
- `Packet Tracer源文件/`
  - `3.pkt`：Packet Tracer 拓扑工程文件
- `Wireshark数据文件/`
  - `iperf_tcp.pcapng`
  - `iperf_udp_small.pcapng`
  - `iperf_udp_large.pcapng`
- `原始数据csv/`
  - `iperf_tcp_5202_filtered.csv`
  - `iperf_udp_small_5202_filtered.csv`
  - `iperf_udp_large_5202_filtered.csv`
- `shiyanFig/`
  - 论文正文中的实验图、抓包图、仿真图
- `Visio图/`
  - `multi_service_fifo_queue_visio.vsdx`

## 使用说明

### 1. Packet Tracer

打开 `Packet Tracer源文件/3.pkt` 查看拓扑或继续修改实验场景。

### 2. Wireshark 抓包数据

`Wireshark数据文件/` 保存了原始抓包文件，可用于复查 ICMP、HTTP、UDP、iperf3 业务流量。

### 3. MATLAB 仿真

运行 `Matlab源代码文件/qos_matlab_simulation.m` 可生成：

- `capture_stats.csv`
- `simulation_metrics.csv`
- `wrr_weight_sensitivity.csv`
- `Matlab源代码文件/figures/` 下的结果图

### 4. 数据文件路径说明

脚本当前默认读取同目录下的：

- `iperf_udp_small.csv`
- `iperf_udp_large.csv`
- `iperf_tcp.csv`

而项目里实际保留的是 `原始数据csv/` 下的 `*_5202_filtered.csv` 文件。

如果直接运行脚本，请先：

1. 将这三个 CSV 复制到 `Matlab源代码文件/`
2. 并重命名为脚本期望的文件名

或者直接修改脚本中的 `csvFiles` 路径。

## 论文图对应关系

`shiyanFig/` 中的图片基本对应论文第 3 章到第 5 章的实验图，包括：

- Packet Tracer 拓扑与配置图
- 真机抓包结果图
- iperf3 对照实验图

## 备注

- 图像文件名已按论文图号整理，便于正文引用。
- 如果你只想复现实验结果，优先使用 `Matlab源代码文件/qos_matlab_simulation.m` 和 `原始数据csv/`。
- 如果你只想查看拓扑，可直接打开 `Packet Tracer源文件/3.pkt`。
