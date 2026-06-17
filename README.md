# MultiService-QoS-Scheduling-WRR

This repository contains a course project on QoS scheduling in multi-service packet-switched networks. The project combines Packet Tracer, iperf3, Wireshark, and MATLAB to analyze how different traffic types compete on a shared bottleneck link.

Packet Tracer is used to build and verify the network topology, including VLANs, routing, servers, and multi-service forwarding paths. iperf3 is used to generate controlled TCP bulk traffic, UDP small-packet traffic, and UDP large-packet traffic. Wireshark captures the real host-side packets and exports CSV data, including timestamps, protocol types, packet lengths, ports, and DSCP fields. MATLAB then uses the measured CSV data to reconstruct packet arrival sequences and service times, and compares FIFO, PQ, and WRR queue scheduling mechanisms.

The project focuses on voice-like small packets, video-like large UDP packets, and data-oriented TCP bulk traffic. Different WRR weight settings are evaluated using delay, jitter, packet loss, throughput satisfaction, and Jain’s fairness index. The results show that WRR with a 3:2:1 weight provides a balanced trade-off between real-time service protection and fairness for ordinary data traffic in small multi-service LAN scenarios.
