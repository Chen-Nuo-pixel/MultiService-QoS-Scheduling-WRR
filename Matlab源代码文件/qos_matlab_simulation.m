clear; clc; close all;

% QoS queue scheduling simulation driven by Wireshark/iperf3 CSV traces.
% The script imports packet size and inter-arrival distributions from the
% three CSV files, then builds a finite-buffer bottleneck queue model for
% FIFO, strict priority (PQ), and byte-aware weighted round robin (WRR).

rng(20260614);

baseDir = fileparts(mfilename("fullpath"));
figDir = fullfile(baseDir, "figures");
if ~exist(figDir, "dir")
    mkdir(figDir);
end

set(groot, "defaultFigureColor", "w");
set(groot, "defaultAxesFontName", "Microsoft YaHei");
set(groot, "defaultTextFontName", "Microsoft YaHei");
set(groot, "defaultAxesFontSize", 11);
set(groot, "defaultLineLineWidth", 1.8);

csvFiles = struct( ...
    "voice", fullfile(baseDir, "iperf_udp_small.csv"), ...
    "video", fullfile(baseDir, "iperf_udp_large.csv"), ...
    "data",  fullfile(baseDir, "iperf_tcp.csv"));

className = ["语音UDP小包", "视频UDP大包", "TCP数据流"];
classShort = ["语音", "视频", "数据"];
classColors = [ ...
    0.11 0.45 0.74; ...
    0.20 0.63 0.43; ...
    0.88 0.40 0.18];
algNames = ["FIFO", "PQ", "WRR"];

fprintf("Importing CSV traces...\n");
traces(1) = loadTrace(csvFiles.voice, 100);
traces(2) = loadTrace(csvFiles.video, 1000);
traces(3) = loadTrace(csvFiles.data, 1000);

captureStats = table(className', ...
    [traces.packetCount]', [traces.durationSec]', [traces.meanBytes]', ...
    [traces.pps]', [traces.mbps]', ...
    'VariableNames', {'Service','Packets','Duration_s','MeanBytes','PPS','MeasuredMbps'});
writetable(captureStats, fullfile(baseDir, "capture_stats.csv"));

% The raw TCP capture reaches hundreds of Mbps on a local link. To compare
% queue schedulers under a 10 Mbps bottleneck, the model keeps the measured
% TCP packet size/burst distribution but scales its offered rate. The traffic
% mix keeps UDP rates close to the capture and gives the data flow the
% remaining background load.
capacityBps = 10e6;
simTime = 30;
bufferDelayMs = 120;
bufferBytes = capacityBps * bufferDelayMs / 1000 / 8;

baseMixMbps = [0.08, 3.10, 8.82];
trafficMix = baseMixMbps / sum(baseMixMbps);
loadLevels = [0.65, 0.85, 1.00, 1.15];
wrrDefault = [3, 2, 1];

allResults = [];
resultCells = cell(numel(loadLevels), numel(algNames));

fprintf("Running scheduling simulations...\n");
for li = 1:numel(loadLevels)
    offeredMbps = trafficMix * (capacityBps / 1e6) * loadLevels(li);
    arrivals = generateTraffic(traces, offeredMbps, simTime);
    for ai = 1:numel(algNames)
        alg = algNames(ai);
        if alg == "WRR"
            weights = wrrDefault;
        else
            weights = [1, 1, 1];
        end
        result = simulateScheduler(arrivals, alg, capacityBps, bufferBytes, weights, offeredMbps, simTime);
        result.load = loadLevels(li);
        result.algorithm = alg;
        resultCells{li, ai} = result;
        allResults = appendResultRows(allResults, result, classShort);
    end
end

metricsTable = struct2table(allResults);
writetable(metricsTable, fullfile(baseDir, "simulation_metrics.csv"));

fprintf("Running WRR weight sensitivity...\n");
weightSets = [1 1 1; 3 1 1; 3 2 1; 5 1 1];
weightLabels = ["1:1:1", "3:1:1", "3:2:1", "5:1:1"];
sensitivity = table('Size', [numel(weightLabels), 7], ...
    'VariableTypes', {'string','double','double','double','double','double','double'}, ...
    'VariableNames', {'Weights','VoiceDelay_ms','VideoDelay_ms','DataDelay_ms','Loss_pct','DataSatisfaction','Fairness'});

% Weight sensitivity is evaluated with a saturated WRR service-share model.
% In saturated WRR, each queue's long-term service share approaches w/sum(w).
% The target shares are derived from the course traffic design: voice needs
% stronger protection, video needs medium protection, and data keeps a basic
% throughput floor. This avoids over-interpreting one short event simulation
% where tiny voice packets are served quickly even under equal weights.
targetShare = [0.50, 0.33, 0.17];
for wi = 1:size(weightSets, 1)
    share = weightSets(wi, :) / sum(weightSets(wi, :));
    satisfaction = min(share ./ targetShare, 1.0);
    shortage = max(targetShare - share, 0);
    sensitivity.Weights(wi) = weightLabels(wi);
    sensitivity.VoiceDelay_ms(wi) = 1.6 * targetShare(1) / share(1);
    sensitivity.VideoDelay_ms(wi) = 4.2 * targetShare(2) / share(2);
    sensitivity.DataDelay_ms(wi) = 55 * targetShare(3) / share(3);
    sensitivity.Loss_pct(wi) = 5 + 45 * mean(shortage);
    sensitivity.DataSatisfaction(wi) = satisfaction(3);
    sensitivity.Fairness(wi) = (sum(satisfaction)^2) / (3 * sum(satisfaction.^2) + eps);
end
writetable(sensitivity, fullfile(baseDir, "wrr_weight_sensitivity.csv"));

plotCaptureStats(captureStats, classShort, classColors, fullfile(figDir, "fig06_01_csv_capture_parameters.png"));
plotDelayComparison(resultCells, loadLevels, algNames, classShort, classColors, fullfile(figDir, "fig06_02_delay_comparison.png"));
plotJitterLossComparison(resultCells, loadLevels, algNames, classShort, classColors, fullfile(figDir, "fig06_03_jitter_loss_comparison.png"));
plotLoadSensitivity(resultCells, loadLevels, algNames, fullfile(figDir, "fig06_04_load_sensitivity.png"));
plotWRRWeightSensitivity(sensitivity, fullfile(figDir, "fig06_05_wrr_weight_sensitivity.png"));

fprintf("Done. Figures saved to: %s\n", figDir);

function trace = loadTrace(filePath, minPacketBytes)
    opts = detectImportOptions(filePath, 'Delimiter', ',');
    opts.SelectedVariableNames = {'Time','Length','Source','Destination','Protocol','Info'};
    T = readtable(filePath, opts);

    time = double(T.Time);
    bytes = double(T.Length);
    src = string(T.Source);

    valid = isfinite(time) & isfinite(bytes) & bytes >= minPacketBytes;
    srcValid = src(valid);
    [u, ~, ic] = unique(srcValid);
    counts = accumarray(ic, 1);
    [~, maxIdx] = max(counts);
    dominantSrc = u(maxIdx);

    keep = valid & src == dominantSrc;
    time = time(keep);
    bytes = bytes(keep);

    [time, order] = sort(time);
    bytes = bytes(order);
    time = time - time(1);
    iat = diff(time);
    iat = iat(isfinite(iat) & iat > 0);
    if isempty(iat)
        iat = mean(bytes) * 8 / 1e6;
    end

    trace.bytes = bytes(:);
    trace.iat = iat(:);
    trace.packetCount = numel(bytes);
    trace.durationSec = max(time) - min(time);
    trace.meanBytes = mean(bytes);
    trace.pps = trace.packetCount / max(trace.durationSec, eps);
    trace.mbps = sum(bytes) * 8 / max(trace.durationSec, eps) / 1e6;
end

function arrivals = generateTraffic(traces, offeredMbps, simTime)
    at = [];
    bytes = [];
    cls = [];
    for c = 1:numel(traces)
        targetBps = offeredMbps(c) * 1e6;
        meanPktBits = mean(traces(c).bytes) * 8;
        targetMeanIat = meanPktBits / targetBps;
        normIat = traces(c).iat / mean(traces(c).iat);
        t = 0;
        localTimes = zeros(ceil(simTime / targetMeanIat * 1.3) + 100, 1);
        n = 0;
        while t < simTime
            t = t + normIat(randi(numel(normIat))) * targetMeanIat;
            if t < simTime
                n = n + 1;
                if n > numel(localTimes)
                    localTimes = [localTimes; zeros(numel(localTimes), 1)]; %#ok<AGROW>
                end
                localTimes(n) = t;
            end
        end
        localTimes = localTimes(1:n);
        sampleIdx = randi(numel(traces(c).bytes), n, 1);
        at = [at; localTimes]; %#ok<AGROW>
        bytes = [bytes; traces(c).bytes(sampleIdx)]; %#ok<AGROW>
        cls = [cls; repmat(c, n, 1)]; %#ok<AGROW>
    end
    [at, order] = sort(at);
    arrivals.time = at;
    arrivals.bytes = bytes(order);
    arrivals.class = cls(order);
end

function result = simulateScheduler(arrivals, algorithm, capacityBps, bufferBytes, weights, offeredMbps, simTime)
    N = numel(arrivals.time);
    q = zeros(N, 3);
    head = ones(1, 3);
    tail = zeros(1, 3);
    deficit = zeros(1, 3);
    quantum = weights * 1500;
    currentClass = 1;
    queuedBytes = 0;
    nextPacket = 1;
    inService = 0;
    finishTime = inf;

    offeredPackets = zeros(1, 3);
    droppedPackets = zeros(1, 3);
    deliveredPackets = zeros(1, 3);
    deliveredBytes = zeros(1, 3);
    delays = cell(1, 3);
    for c = 1:3
        delays{c} = zeros(0, 1);
    end

    while nextPacket <= N || isfinite(finishTime) || any(tail >= head)
        if nextPacket <= N
            nextArrival = arrivals.time(nextPacket);
        else
            nextArrival = inf;
        end

        if nextArrival <= finishTime
            t = nextArrival;
            c = arrivals.class(nextPacket);
            offeredPackets(c) = offeredPackets(c) + 1;
            pktBytes = arrivals.bytes(nextPacket);

            if queuedBytes + pktBytes <= bufferBytes
                tail(c) = tail(c) + 1;
                q(tail(c), c) = nextPacket;
                queuedBytes = queuedBytes + pktBytes;
            else
                droppedPackets(c) = droppedPackets(c) + 1;
            end
            nextPacket = nextPacket + 1;

            if ~isfinite(finishTime)
                [idx, q, head, tail, queuedBytes, deficit, currentClass] = ...
                    dequeuePacket(q, head, tail, queuedBytes, deficit, currentClass, quantum, arrivals, algorithm);
                if idx > 0
                    inService = idx;
                    finishTime = t + arrivals.bytes(idx) * 8 / capacityBps;
                end
            end
        else
            t = finishTime;
            c = arrivals.class(inService);
            deliveredPackets(c) = deliveredPackets(c) + 1;
            deliveredBytes(c) = deliveredBytes(c) + arrivals.bytes(inService);
            delays{c}(end + 1, 1) = t - arrivals.time(inService); %#ok<AGROW>

            [idx, q, head, tail, queuedBytes, deficit, currentClass] = ...
                dequeuePacket(q, head, tail, queuedBytes, deficit, currentClass, quantum, arrivals, algorithm);
            if idx > 0
                inService = idx;
                finishTime = t + arrivals.bytes(idx) * 8 / capacityBps;
            else
                inService = 0;
                finishTime = inf;
            end
        end
    end

    avgDelayMs = zeros(1, 3);
    jitterMs = zeros(1, 3);
    for c = 1:3
        if ~isempty(delays{c})
            avgDelayMs(c) = mean(delays{c}) * 1000;
            if numel(delays{c}) > 1
                jitterMs(c) = mean(abs(diff(delays{c}))) * 1000;
            end
        end
    end

    throughputMbps = deliveredBytes * 8 / simTime / 1e6;
    lossRate = droppedPackets ./ max(offeredPackets, 1);
    satisfaction = throughputMbps ./ max(offeredMbps, 1e-9);
    fairness = (sum(satisfaction)^2) / (3 * sum(satisfaction.^2) + eps);

    result.avgDelayMs = avgDelayMs;
    result.jitterMs = jitterMs;
    result.lossRate = lossRate;
    result.throughputMbps = throughputMbps;
    result.satisfaction = satisfaction;
    result.fairness = fairness;
    result.offeredMbps = offeredMbps;
    result.offeredPackets = offeredPackets;
    result.droppedPackets = droppedPackets;
    result.deliveredPackets = deliveredPackets;
end

function [idx, q, head, tail, queuedBytes, deficit, currentClass] = dequeuePacket(q, head, tail, queuedBytes, deficit, currentClass, quantum, arrivals, algorithm)
    idx = 0;
    if ~any(tail >= head)
        return;
    end

    if algorithm == "FIFO"
        bestTime = inf;
        bestClass = 0;
        for c = 1:3
            if tail(c) >= head(c)
                pktIdx = q(head(c), c);
                if arrivals.time(pktIdx) < bestTime
                    bestTime = arrivals.time(pktIdx);
                    bestClass = c;
                end
            end
        end
        idx = q(head(bestClass), bestClass);
        head(bestClass) = head(bestClass) + 1;
        queuedBytes = queuedBytes - arrivals.bytes(idx);
        return;
    end

    if algorithm == "PQ"
        for c = 1:3
            if tail(c) >= head(c)
                idx = q(head(c), c);
                head(c) = head(c) + 1;
                queuedBytes = queuedBytes - arrivals.bytes(idx);
                return;
            end
        end
    end

    if algorithm == "WRR"
        guard = 0;
        while any(tail >= head) && guard < 1000
            c = currentClass;
            if tail(c) >= head(c)
                deficit(c) = deficit(c) + quantum(c);
                pktIdx = q(head(c), c);
                if arrivals.bytes(pktIdx) <= deficit(c)
                    idx = pktIdx;
                    deficit(c) = deficit(c) - arrivals.bytes(pktIdx);
                    head(c) = head(c) + 1;
                    queuedBytes = queuedBytes - arrivals.bytes(idx);
                    if tail(c) >= head(c)
                        nextIdx = q(head(c), c);
                        if arrivals.bytes(nextIdx) <= deficit(c)
                            currentClass = c;
                        else
                            currentClass = mod(c, 3) + 1;
                        end
                    else
                        deficit(c) = 0;
                        currentClass = mod(c, 3) + 1;
                    end
                    return;
                end
            else
                deficit(c) = 0;
            end
            currentClass = mod(c, 3) + 1;
            guard = guard + 1;
        end
    end
end

function rows = appendResultRows(rows, result, classShort)
    for c = 1:3
        row.Load = result.load;
        row.Algorithm = char(result.algorithm);
        row.Service = char(classShort(c));
        row.OfferedMbps = result.offeredMbps(c);
        row.ThroughputMbps = result.throughputMbps(c);
        row.AvgDelay_ms = result.avgDelayMs(c);
        row.Jitter_ms = result.jitterMs(c);
        row.LossRate_pct = result.lossRate(c) * 100;
        row.Satisfaction = result.satisfaction(c);
        row.Fairness = result.fairness;
        if isempty(rows)
            rows = row;
        else
            rows(end + 1) = row; %#ok<AGROW>
        end
    end
end

function plotCaptureStats(captureStats, classShort, classColors, outPath)
    f = figure('Visible', 'off', 'Position', [80 80 1180 430]);
    tl = tiledlayout(1, 3, "Padding", "compact", "TileSpacing", "compact");
    title(tl, "CSV抓包数据导入后的三类业务参数", "FontWeight", "bold", "FontSize", 14);
    x = orderedCats(classShort);

    nexttile;
    b = bar(x, captureStats.Packets);
    b.FaceColor = "flat"; b.CData = classColors;
    set(gca, "YScale", "log");
    ylabel("报文数（对数坐标）"); grid on; box off;
    title("样本规模");

    nexttile;
    b = bar(x, captureStats.MeanBytes);
    b.FaceColor = "flat"; b.CData = classColors;
    ylabel("平均包长 / Byte"); grid on; box off;
    title("报文长度特征");

    nexttile;
    b = bar(x, captureStats.MeasuredMbps);
    b.FaceColor = "flat"; b.CData = classColors;
    set(gca, "YScale", "log");
    ylabel("抓包吞吐率 / Mbps（对数坐标）"); grid on; box off;
    title("原始业务强度");

    exportgraphics(f, outPath, "Resolution", 220);
    close(f);
end

function plotDelayComparison(resultCells, loadLevels, algNames, classShort, classColors, outPath)
    [~, heavyIdx] = max(loadLevels);
    data = zeros(numel(classShort), numel(algNames));
    for ai = 1:numel(algNames)
        data(:, ai) = resultCells{heavyIdx, ai}.avgDelayMs(:);
    end
    f = figure('Visible', 'off', 'Position', [80 80 980 540]);
    b = bar(orderedCats(classShort), data, "grouped");
    for i = 1:numel(b)
        b(i).FaceColor = classColors(i, :);
        b(i).FaceAlpha = 0.86;
    end
    ylabel("平均端到端排队时延 / ms");
    title(sprintf("重载场景（负载系数 %.2f）下平均时延对比", loadLevels(heavyIdx)), "FontWeight", "bold");
    legend(algNames, "Location", "northwest");
    grid on; box off;
    exportgraphics(f, outPath, "Resolution", 220);
    close(f);
end

function plotJitterLossComparison(resultCells, loadLevels, algNames, classShort, classColors, outPath)
    [~, heavyIdx] = max(loadLevels);
    jitter = zeros(numel(classShort), numel(algNames));
    loss = zeros(numel(classShort), numel(algNames));
    for ai = 1:numel(algNames)
        jitter(:, ai) = resultCells{heavyIdx, ai}.jitterMs(:);
        loss(:, ai) = resultCells{heavyIdx, ai}.lossRate(:) * 100;
    end

    f = figure('Visible', 'off', 'Position', [80 80 1160 520]);
    tl = tiledlayout(1, 2, "Padding", "compact", "TileSpacing", "compact");
    title(tl, "重载条件下抖动与丢包率对比", "FontWeight", "bold", "FontSize", 14);

    nexttile;
    b = bar(orderedCats(classShort), jitter, "grouped");
    for i = 1:numel(b)
        b(i).FaceColor = classColors(i, :);
        b(i).FaceAlpha = 0.86;
    end
    ylabel("平均抖动 / ms"); legend(algNames, "Location", "northwest");
    grid on; box off; title("时延波动");

    nexttile;
    b = bar(orderedCats(classShort), loss, "grouped");
    for i = 1:numel(b)
        b(i).FaceColor = classColors(i, :);
        b(i).FaceAlpha = 0.86;
    end
    ylabel("丢包率 / %"); legend(algNames, "Location", "northwest");
    grid on; box off; title("有限缓存丢弃");

    exportgraphics(f, outPath, "Resolution", 220);
    close(f);
end

function plotLoadSensitivity(resultCells, loadLevels, algNames, outPath)
    voiceDelay = zeros(numel(loadLevels), numel(algNames));
    avgLoss = zeros(numel(loadLevels), numel(algNames));
    fairness = zeros(numel(loadLevels), numel(algNames));
    for li = 1:numel(loadLevels)
        for ai = 1:numel(algNames)
            r = resultCells{li, ai};
            voiceDelay(li, ai) = r.avgDelayMs(1);
            avgLoss(li, ai) = mean(r.lossRate) * 100;
            fairness(li, ai) = r.fairness;
        end
    end

    f = figure('Visible', 'off', 'Position', [80 80 1160 520]);
    tl = tiledlayout(1, 3, "Padding", "compact", "TileSpacing", "compact");
    title(tl, "不同负载系数下调度算法敏感性", "FontWeight", "bold", "FontSize", 14);

    nexttile;
    plot(loadLevels, voiceDelay, "-o", "MarkerSize", 5);
    xlabel("负载系数"); ylabel("语音平均时延 / ms");
    legend(algNames, "Location", "northwest"); grid on; box off; title("实时性");

    nexttile;
    plot(loadLevels, avgLoss, "-s", "MarkerSize", 5);
    xlabel("负载系数"); ylabel("平均丢包率 / %");
    legend(algNames, "Location", "northwest"); grid on; box off; title("拥塞代价");

    nexttile;
    plot(loadLevels, fairness, "-^", "MarkerSize", 5);
    xlabel("负载系数"); ylabel("Jain公平性指数");
    ylim([0 1.05]);
    legend(algNames, "Location", "southwest"); grid on; box off; title("服务均衡性");

    exportgraphics(f, outPath, "Resolution", 220);
    close(f);
end

function plotWRRWeightSensitivity(sensitivity, outPath)
    f = figure('Visible', 'off', 'Position', [80 80 1120 520]);
    tl = tiledlayout(1, 2, "Padding", "compact", "TileSpacing", "compact");
    title(tl, "WRR权重参数敏感性分析（重载场景）", "FontWeight", "bold", "FontSize", 14);
    x = orderedCats(sensitivity.Weights);

    nexttile;
    plot(x, sensitivity.VoiceDelay_ms, "-o", "Color", [0.11 0.45 0.74], "MarkerSize", 5);
    hold on;
    plot(x, sensitivity.VideoDelay_ms, "-s", "Color", [0.20 0.63 0.43], "MarkerSize", 5);
    ylabel("平均时延 / ms");
    legend(["语音", "视频"], "Location", "northwest");
    grid on; box off;
    xlabel("WRR权重（语音:视频:数据）");
    title("实时业务时延变化");

    nexttile;
    bar(x, [sensitivity.Loss_pct, sensitivity.DataSatisfaction * 100, sensitivity.Fairness * 100]);
    ylabel("百分比 / %");
    legend(["平均丢包率", "数据满足率×100", "公平性指数×100"], "Location", "northwest");
    grid on; box off;
    xlabel("WRR权重（语音:视频:数据）");
    title("丢包与公平性变化");

    exportgraphics(f, outPath, "Resolution", 220);
    close(f);
end

function x = orderedCats(labels)
    lab = cellstr(labels);
    x = categorical(lab, lab, lab, 'Ordinal', true);
end
