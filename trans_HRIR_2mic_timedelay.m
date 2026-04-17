%% ========================================================================
% 麦克风阵列 HRIR 生成器 (WAV格式 & 坐标映射保存版)
% ========================================================================
clear; close all; clc;

%% 1. 环境准备与数据加载
data_file = 'hrir_final.mat'; 
if ~exist(data_file, 'file'), error('找不到数据文件 %s', data_file); end
load(data_file);

hrir = hrir_l;
[nAzi, nEle, nSamp_in] = size(hrir);
azimuth_vals = [-80, -65, -55, -45:5:45, 55, 65, 80];
elevation_vals = -45 + 5.625*(0:49);

% --- 用户参数设置 ---
azi_idx = 1;    % 示例方位角索引  13为0  1为-80 25为80
ele_idx = 9;   % 示例仰角索引 (如对应180°左右)  41/9
fs_out = 16000; 
for i = 1:25
    azi_idx = i;
azi_deg = azimuth_vals(azi_idx);
ele_deg = elevation_vals(ele_idx);
h1_orig = squeeze(hrir(azi_idx, ele_idx, :));

%% 2. 几何时延计算 (基于1cm间距)
c = 343; R_head = 0.0875; d_mic = 0.01; r_source = 1.0;
p1 = [0, R_head, 0];    
p2 = [p1(1) + d_mic, p1(2), p1(3)]; 
az_rad = deg2rad(azi_deg); el_rad = deg2rad(ele_deg);
source_dir = [cos(el_rad)*cos(az_rad), cos(el_rad)*sin(az_rad), sin(el_rad)];
Ps = r_source * source_dir;

dist1 = norm(Ps - p1); dist2 = norm(Ps - p2);
delta_t = (dist2 - dist1) / c; 
theory_delay_samples = delta_t * fs_out;

%% 3. 时域处理：重采样与样条插值平移 (自适应修正版)

% A. 首先将 Mic1 重采样到目标频率
[p, q] = rat(fs_out / 44100);
h1_resampled = resample(h1_orig, p, q);

N_samples = length(h1_resampled);
t_orig = (0:N_samples-1)' / fs_out;

% 对称平移：Mic1 向左移半个 dt，Mic2 向右移半个 dt
% 这样总延迟差正好是 delta_t
t_target1 = t_orig + (delta_t / 2); 
t_target2 = t_orig - (delta_t / 2);

h1_final = interp1(t_orig, h1_resampled, t_target1, 'spline', 0);
h2_final = interp1(t_orig, h1_resampled, t_target2, 'spline', 0);

% 检查：如果 0° 时 delta_t 是负数
% h1_final 采样点 = t - |dt|/2 (右移/延迟)
% h2_final 采样点 = t + |dt|/2 (左移/提前)
% 结果：Mic2 先于 Mic1，符合物理。
%% 4. 文件夹命名逻辑与 WAV 保存

% --- A. 坐标映射逻辑 ---
final_angle = azi_deg;

% 1. 若仰角为 180°，方位角加 180
if abs(ele_deg - 180) < 0.1
    final_angle =  180 - final_angle;


% 2. 若方位角为负，加 360
elseif final_angle < 0
    final_angle = final_angle + 360;
end

% 格式化文件夹名称（保留一位小数或取整）
folder_name = sprintf('%.1d', final_angle);

% 创建文件夹
if ~exist(folder_name, 'dir'), mkdir(folder_name); end

% --- B. 确定文件名 (01.wav, 02.wav...) ---
existing_wavs = dir(fullfile(folder_name, '*.wav'));
file_count = length(existing_wavs) + 1;
file_name = sprintf('%02d.wav', file_count);
save_path = fullfile(folder_name, file_name);

% --- C. 写入 WAV 文件 (双声道) ---
% 拼接为 [N x 2] 矩阵
y_wav = [h1_final(:), h2_final(:)]; 
audiowrite(save_path, y_wav, fs_out, 'BitsPerSample', 16);

fprintf('\n================ 保存报告 =================\n');
fprintf('原始角度: Azi %.1f°, Ele %.1f°\n', azi_deg, ele_deg);
fprintf('映射后文件夹名: %s\n', folder_name);
fprintf('文件名: %s\n', file_name);
fprintf('采样率: %d Hz\n', fs_out);
fprintf('状态: 双声道音频已保存至 %s\n', save_path);
fprintf('===========================================\n');
end