%% 自动化波束形成处理：自适应输入/输出结构版
clear; close all; clc;

% --- 路径设置 ---
% 模式1：'.../测试白噪10mm' 下有 0, 30, 60 子文件夹
% 模式2：'.../测试白噪10mm' 下直接是 1.wav, 2.wav (1=0°, 2=30°)
%  第84/85行决定是否翻转  DNN-HRIR需要反转
data_path = 'E:\JHY\rentou\3d\AA_timedelay\亿联人工头-DLSOB\亿联测试22.7.23\分割后\10mm消声室人工头\人声\f1'; 
output_path = 'E:\JHY\rentou\3d\AA_timedelay\亿联人工头-DLSOB\人声-DLSOB'; 
 coef_path = 'E:\JHY\rentou\comsol-exp\2d-\matlab代码\10mm系数\DLSOB.mat';
% coef_path = 'E:\JHY\rentou\3d\DNN\pythonProject\models_hrir_v3\model_e158.mat';

% --- 参数设置 ---
Fs1 = 16000;       
lt = 128;           
Channel = 2;       
b = 0.1;           % 增益系数

% 1. 加载并准备系数
if ~exist(coef_path, 'file'), error('找不到系数文件'); end
load(coef_path);   
fw2 = fw; 
dnn_coef = zeros(Channel, lt);
for n = 1:Channel
    dnn_coef(n,:) = fft(fw2(n,:)); 
end

% 2. 结构判定：探测输入目录
allEntries = dir(data_path);
% 过滤掉 '.' 和 '..'
allEntries = allEntries(~ismember({allEntries.name}, {'.', '..'}));
dirFlags = [allEntries.isdir];
subDirs = allEntries(dirFlags);
% 检查是否存在数字命名的子文件夹
validDirIdx = ~cellfun(@isempty, regexp({subDirs.name}, '^\d+$'));
targetAzDirs = subDirs(validDirIdx);

taskList = {};
isFolderMode = ~isempty(targetAzDirs); % 判定当前是什么模式

if isFolderMode
    fprintf('检查到【子文件夹模式】，输出将保持文件夹结构...\n');
    for j = 1:length(targetAzDirs)
        azName = targetAzDirs(j).name;
        wavs = dir(fullfile(data_path, azName, '*.wav'));
        for k = 1:length(wavs)
            % 任务：[输入全路径, 输出文件夹, 输出文件名]
            taskList(end+1, :) = {fullfile(data_path, azName, wavs(k).name), ...
                                  fullfile(output_path, azName), ...
                                  wavs(k).name};
        end
    end
else
    fprintf('检查到【单一文件夹模式】，输出将保存在单一文件夹内...\n');
    wavs = dir(fullfile(data_path, '*.wav'));
    % 仅处理数字命名的 wav
    validWavIdx = ~cellfun(@isempty, regexp({wavs.name}, '^\d+\.wav$'));
    targetWavs = wavs(validWavIdx);
    
    if ~exist(output_path, 'dir'), mkdir(output_path); end
    
    for k = 1:length(targetWavs)
        fName = targetWavs(k).name;
        % 在单一文件夹模式下，输出路径就是 output_path 本身
        % 为了防止重名或方便识别，输出文件名保持原样 (1.wav, 2.wav...)
        taskList(end+1, :) = {fullfile(data_path, fName), ...
                              output_path, ...
                              fName};
    end
end

if isempty(taskList), error('未找到有效音频文件。'); end

% 3. 统一处理循环
for t = 1:size(taskList, 1)
    inPath = taskList{t, 1};
    outDir = taskList{t, 2};
    outFile = taskList{t, 3};
    
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    
    % A. 读取与重采样
    [signal, fs_read] = audioread(inPath);
%     signal2 = signal;
%         signal(:,1) = signal2(:,2);    %此处根据滤波器系数选择是否翻转
%         signal(:,2) = signal2(:,1);         
    if fs_read ~= Fs1, signal = resample(signal, Fs1, fs_read); end
    
    % B. 数据准备
    AD = signal'; 
    len = floor(size(AD, 2) / lt) * lt;
    testax = AD(:, 1:len);
    
    % C. 计算 vxx (用于能量对齐，确保不同信号下波束图形状一致)
    vxx = 0.5 * (var(testax(1,:)) + var(testax(2,:)));
    
    % D. 频域波束形成
    [yout_dnn] = freq_beamforming_xmu(Channel, testax, len, lt, dnn_coef);
    
    % E. 后处理 (采用 mean + 归一化对齐)
    bfout = mean(yout_dnn, 1);
    
    % --- 关键对齐步骤 ---
    % 如果你想让抑制深度从 -27dB 变回 -18dB 左右（对齐实测组），
    % 请确保这里的归一化逻辑生效：
    bfout = 0.5 * bfout / (sqrt(vxx) + eps); 
    
    % 应用最终增益 b
    final_sig = b * bfout;
    
    % F. 保存
    audiowrite(fullfile(outDir, outFile), final_sig, Fs1);
    
    if mod(t, 10) == 0, fprintf('已处理: %d/%d\n', t, size(taskList,1)); end
end

disp('--- 处理完成：输出格式已与输入格式对应 ---');