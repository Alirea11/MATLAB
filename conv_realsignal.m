%% 信号处理：单通道信号与双通道 IR 的频域卷积
clear; clc;

% --- 参数设置 ---
targetFs = 16000;      % 计算采样率 (160kHz)
originalFs = 16000;     % 原始/输出采样率 (16kHz)
inputSignalPath = 'E:\JHY\rentou\3d\AA_timedelay\纯净音频切割\白噪\1.wav';
outputBaseDir = '白噪HRIR卷积后16k';

% 1. 读取并预处理纯净信号 (16kHz 单通道 -> 160kHz)
if ~exist(inputSignalPath, 'file')
    error('未找到原始信号文件：%s', inputSignalPath);
end
[sig, fs] = audioread(inputSignalPath);

% 强制转为单通道（以防万一）
if size(sig, 2) > 1
    sig = mean(sig, 2); 
end

% 升采样到 160kHz
sig_160k = resample(sig, targetFs, originalFs);

% 2. 搜索方位角文件夹
allFiles = dir();
azDirs = allFiles([allFiles.isdir]);
validDirIndices = ~cellfun(@isempty, regexp({azDirs.name}, '^\d+$'));
azDirs = azDirs(validDirIndices);

% 3. 遍历方位角文件夹
for i = 1:length(azDirs)
    azName = azDirs(i).name; 
    wavFiles = dir(fullfile(azName, '*.wav'));
    
    if isempty(wavFiles), continue; end
    
    outputFolder = fullfile(outputBaseDir, azName);
    if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

    % 4. 遍历当前文件夹内的 IR 文件
    for j = 1:length(wavFiles)
        irFileName = wavFiles(j).name;
        irPath = fullfile(azName, irFileName);
        
        % 读取双通道冲激响应 (预期 160kHz)
        [ir, fs_ir] = audioread(irPath);
        if fs_ir ~= targetFs
            ir = resample(ir, targetFs, fs_ir);
        end
        
        % 确定 IR 的通道数 (应为 2)
        numChannels = size(ir, 2);
        
        % --- 诊断：检查原始 IR 的峰值位置 ---
[~, p1] = max(abs(ir(:,1)));
[~, p2] = max(abs(ir(:,2)));
diff_ir = p2 - p1; 
fprintf('方位角 %s: 通道1峰值@%d, 通道2峰值@%d, 相对延迟: %d 个采样点\n', ...
    azName, p1, p2, diff_ir);
        % 5. 频域卷积准备
        L_sig = length(sig_160k);
        L_ir = length(ir);
        L_total = L_sig + L_ir - 1;
        nfft = 2^nextpow2(L_total); 
        
        SIG = fft(sig_160k, nfft);
        conv_stereo_160k = zeros(nfft, numChannels);
        
        for ch = 1:numChannels
            IR_CH = fft(ir(:, ch), nfft);
            % 执行卷积
            TEMP_RES = ifft(SIG .* IR_CH);
            conv_stereo_160k(:, ch) = real(TEMP_RES);
        end
        
        % --- 关键改进：自动寻找包络起点进行截取 ---
        % 不再盲目取 1:L，而是根据 IR 的能量中心或直接取有效长度
        % 确保左右声道的相对时间轴不做任何独立滑动
        conv_result = conv_stereo_160k(1:L_total, :);
% --- [修改部分开始] ---
        
        % 1. 截取有效长度并降采样 (160kHz -> 16kHz)
        % 注意：resample 建议在归一化前进行，以保证能量计算的频域一致性
        final_signal = resample(conv_stereo_160k(1:L_total, :), originalFs, targetFs);

        % 2. 计算输入参考能量 (对应第二段代码的 vxx)
        % 我们以卷积后的双通道平均方差作为基准，这样可以抵消输入信号的幅值影响
        vxx_current = 0.5 * (var(final_signal(:,1)) + var(final_signal(:,2)));
        
        % 3. 执行对齐归一化
        % 这里乘以 0.5 是为了完全匹配第二段代码中的: y = 0.5 * bfout / sqrt(vxx)
        % 这样处理后的信号在进入 bf_energy 时，其量级与实测代码一致
        final_signal = 0.5 * final_signal / (sqrt(vxx_current) + eps);

        % 4. 最终安全性检查（防止极个别点溢出 1.0）
        % 注意：这里不再除以 max，因为除以 max 会破坏我们刚刚建立的 sqrt(vxx) 能量基准
        % 仅在绝对值大于 1 时进行限幅或微调
        if max(abs(final_signal(:))) > 1.0
            final_signal = final_signal / (max(abs(final_signal(:))) + eps);
        end
        
        % --- [修改部分结束] ---

        % 保存为双通道 wav
        outputPath = fullfile(outputFolder, irFileName);
        audiowrite(outputPath, final_signal, originalFs);
        fprintf('已处理双通道：[%s] -> %s\n', azName, irFileName);
    end
end

disp('--- 任务全部完成！ ---');