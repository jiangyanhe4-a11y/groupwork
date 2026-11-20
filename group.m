%% AoI Simulation: Outer parameter sweep + 10 seeds + 95% CI + errorbar comparison plot (Modified)
clear; clc; close all;

%% ========== Basic fixed parameters ==========
N_sensor = 4;
T_tx = 0.5;
sim_time = 1000; % Increase simulation time for more stable statistical properties
dt = 0.01;
max_queue_len = 3;
priority = [1, 1, 2, 2]; 
warmup_time = 100; % Warm-up time; data from the first 100s is excluded from statistics to avoid initial state effects

%% ========== Sweep parameter settings ==========
T_gen_list = [1, 2, 4, 8];        % Average packet generation interval
p_loss_list = [0, 0.1, 0.3];      % Packet loss rates specified in the task
policy_list = [1,2,3];
policy_name = {"FIFO","Latest Replace","AoI-Priority"};
n_seed = 10;                      % 10 random seeds per combination
t_val = 2.2622;                   % n=10, 95% t-distribution critical value

% Storage: meanAoi( p_idx, T_idx, policy_idx, seed )
n_p = length(p_loss_list);
n_T = length(T_gen_list);
n_pol = length(policy_list);
meanAoi_all = zeros(n_p, n_T, n_pol, n_seed);
peakAoi_all = zeros(n_p, n_T, n_pol, n_seed);
delay_all = zeros(n_p, n_T, n_pol, n_seed);
tx_count_all = zeros(n_p, n_T, n_pol, n_seed);

%% ========== Multi-layer loops ==========
for p_idx = 1:n_p
    p_loss = p_loss_list(p_idx);
    for T_idx = 1:n_T
        T_gen = T_gen_list(T_idx);
        for pol_idx = 1:n_pol
            policy_type = policy_list(pol_idx);
            for seed = 1:n_seed
                rng(seed);
                current_time = 0;
                channel_busy = false;
                tx_start_time = 0;
                tx_packet = [];
                gateway_queue = []; % Format: [sid, gen_time, priority]
                
                % Initialize the last reception time for all sensors to 0 to avoid excessively large initial AoI
                last_gen_recv = zeros(N_sensor, 1); 
                
                % Preallocate memory to improve execution speed
                max_steps = ceil(sim_time/dt);
                log_aoi = zeros(1, max_steps);
                log_step = 0;
                
                delay_log = []; % Record transmission delay
                tx_count = 0;   % Record the number of successfully transmitted packets

                while current_time < sim_time
                    % 1. Poisson packet generation by sensors
                    for sid = 1:N_sensor
                        if rand() < dt / T_gen
                            new_pkt = [sid, current_time, priority(sid)];
                            
                            if policy_type == 1
                                % FIFO policy
                                gateway_queue = [gateway_queue; new_pkt];
                                if size(gateway_queue,1) > max_queue_len
                                    gateway_queue(1,:) = []; % Drop the oldest packet if the queue is full
                                end
                                
                            elseif policy_type == 2
                                % Latest replacement policy
                                % Fix: Check if the queue is empty first
                                if ~isempty(gateway_queue)
                                    gateway_queue(gateway_queue(:,1) == sid, :) = [];
                                end
                                gateway_queue = [gateway_queue; new_pkt];
                                if size(gateway_queue,1) > max_queue_len
                                    gateway_queue(1,:) = []; % Drop the oldest packet if the queue is full
                                end
                                
                            elseif policy_type == 3
                                % AoI + Priority policy
                                % Fix: Check if the queue is empty first
                                if ~isempty(gateway_queue)
                                    gateway_queue(gateway_queue(:,1) == sid, :) = [];
                                end
                                gateway_queue = [gateway_queue; new_pkt];
                                % Sort: first by priority in descending order (3 first), then by generation time in descending order (newest first)
                                gateway_queue = sortrows(gateway_queue, [-3, -2]);
                                if size(gateway_queue,1) > max_queue_len
                                    gateway_queue = gateway_queue(1:max_queue_len, :); % Truncate by dropping the ones at the end
                                end
                            end
                        end
                    end

                    % 2. Link scheduling (transmit only the first packet in the queue at a time)
                    if ~channel_busy && ~isempty(gateway_queue)
                        tx_packet = gateway_queue(1,:);
                        gateway_queue(1,:) = [];  % <--- The queue becomes empty here when only 1 packet is left
                        channel_busy = true;
                        tx_start_time = current_time;
                    end

                    % 3. Transmission completion + packet loss processing
                    if channel_busy && (current_time - tx_start_time >= T_tx)
                        channel_busy = false;
                        if rand() > p_loss % No packet loss
                            sid = tx_packet(1);
                            gen_t = tx_packet(2);
                            last_gen_recv(sid) = gen_t;
                            
                            % Record delay and successful packet count
                            delay_log = [delay_log, current_time - gen_t];
                            tx_count = tx_count + 1;
                        end
                        tx_packet = [];
                    end

                    % 4. Calculate and record AoI
                    aoi_inst = current_time - last_gen_recv; 
                    mean_aoi = mean(aoi_inst); % Average AoI across all sensors
                    
                    % Record data only after the warm-up period
                    if current_time > warmup_time
                        log_step = log_step + 1;
                        log_aoi(log_step) = mean_aoi;
                    end

                    current_time = current_time + dt;
                end
                
                % Extract valid data
                log_aoi = log_aoi(1:log_step);
                
                % Store results
                meanAoi_all(p_idx, T_idx, pol_idx, seed) = mean(log_aoi);
                peakAoi_all(p_idx, T_idx, pol_idx, seed) = max(log_aoi);
                delay_all(p_idx, T_idx, pol_idx, seed) = mean(delay_log);
                tx_count_all(p_idx, T_idx, pol_idx, seed) = tx_count;
            end
        end
        fprintf('Finished p_loss=%.1f, T_gen=%d\n',p_loss, T_gen);
    end
end

%% ========== Statistics: Mean, standard deviation, confidence intervals ==========
meanAoi = zeros(n_p, n_T, n_pol);
stdAoi = zeros(n_p, n_T, n_pol);
ciAoi = zeros(n_p, n_T, n_pol);

for p_idx = 1:n_p
    for T_idx = 1:n_T
        for pol_idx = 1:n_pol
            data = squeeze(meanAoi_all(p_idx, T_idx, pol_idx, :));
            meanAoi(p_idx,T_idx,pol_idx) = mean(data);
            stdAoi(p_idx,T_idx,pol_idx) = std(data);
            % Calculate 95% confidence interval
            ciAoi(p_idx,T_idx,pol_idx) = t_val * stdAoi(p_idx,T_idx,pol_idx)/sqrt(n_seed);
        end
    end
end

%% ========== Plotting: One errorbar plot per loss rate (x-axis is T_gen) ==========
color_list = {'r','g','b'};
marker_list = {'o','s','^'};

for p_idx = 1:n_p
    figure('Color','w', 'Position', [100+p_idx*100, 100, 600, 400]);
    hold on; grid on;
    for pol_idx = 1:n_pol
        x = T_gen_list;
        y = meanAoi(p_idx,:,pol_idx);
        err = ciAoi(p_idx,:,pol_idx);
        errorbar(x, y, err, [color_list{pol_idx}], ...
            'Marker',marker_list{pol_idx},'LineWidth',1.5, 'MarkerSize', 8);
    end
    xlabel('Packet Generation Interval T_{gen} (s)', 'FontSize', 12);
    ylabel('Mean AoI (s)', 'FontSize', 12);
    title(['Mean AoI under Loss rate = ',num2str(p_loss_list(p_idx))], 'FontSize', 14);
    legend(policy_name,'Location','best', 'FontSize', 11);
    hold off;
end

%% ========== Output tables to command window for easy copying to the report ==========
fprintf('\n==== Mean AoI Table (rows:T_gen, columns:FIFO / Latest / AoI-Priority) ====\n');
for p_idx = 1:n_p
    fprintf('\n----- Loss = %.1f -----\n',p_loss_list(p_idx));
    for T_idx = 1:n_T
        fprintf('T_gen=%d: %.2f\t%.2f\t%.2f\n',...
            T_gen_list(T_idx), meanAoi(p_idx,T_idx,1), meanAoi(p_idx,T_idx,2), meanAoi(p_idx,T_idx,3));
    end
end

% Additional printout of average Delivery Delay and Transmitted Packets (for the report)
fprintf('\n==== Average Delivery Delay & Tx Packets (Loss = 0.1) ====\n');
fprintf('T_gen\tFIFO_Delay\tLatest_Delay\tAoI_Delay\n');
for T_idx = 1:n_T
    fprintf('%d\t%.2f\t\t%.2f\t\t%.2f\n', T_gen_list(T_idx), ...
        mean(squeeze(delay_all(2, T_idx, 1, :))), ...
        mean(squeeze(delay_all(2, T_idx, 2, :))), ...
        mean(squeeze(delay_all(2, T_idx, 3, :))));
end
% %% AoI 仿真 外层扫参 + 10种子 + 95%置信区间 + errorbar对比图 (修改版)
% clear; clc; close all;
% 
% %% ========== 基础固定参数 ==========
% N_sensor = 4;
% T_tx = 0.5;
% sim_time = 1000; % 增加仿真时间，使统计特性更稳定
% dt = 0.01;
% max_queue_len = 3;
% priority = [1, 1, 2, 2]; 
% warmup_time = 100; % 预热时间，前100秒的数据不参与统计，避免初始状态影响
% 
% %% ========== 扫参设置 ==========
% T_gen_list = [1, 2, 4, 8];        % 包平均生成间隔
% p_loss_list = [0, 0.1, 0.3];      % 题目指定丢包率
% policy_list = [1,2,3];
% policy_name = {"FIFO","Latest Replace","AoI-Priority"};
% n_seed = 10;                      % 每个组合10个随机种子
% t_val = 2.2622;                   % n=10, 95% t分布分位数
% 
% % 存储：meanAoi( p_idx, T_idx, policy_idx, seed )
% n_p = length(p_loss_list);
% n_T = length(T_gen_list);
% n_pol = length(policy_list);
% meanAoi_all = zeros(n_p, n_T, n_pol, n_seed);
% peakAoi_all = zeros(n_p, n_T, n_pol, n_seed);
% delay_all = zeros(n_p, n_T, n_pol, n_seed);
% tx_count_all = zeros(n_p, n_T, n_pol, n_seed);
% 
% %% ========== 多层循环 ==========
% for p_idx = 1:n_p
%     p_loss = p_loss_list(p_idx);
%     for T_idx = 1:n_T
%         T_gen = T_gen_list(T_idx);
%         for pol_idx = 1:n_pol
%             policy_type = policy_list(pol_idx);
%             for seed = 1:n_seed
%                 rng(seed);
%                 current_time = 0;
%                 channel_busy = false;
%                 tx_start_time = 0;
%                 tx_packet = [];
%                 gateway_queue = []; % 格式: [sid, gen_time, priority]
% 
%                 % 初始化所有传感器的最后接收时间为0，避免初始AoI过大
%                 last_gen_recv = zeros(N_sensor, 1); 
% 
%                 % 预分配内存，提高运行速度
%                 max_steps = ceil(sim_time/dt);
%                 log_aoi = zeros(1, max_steps);
%                 log_step = 0;
% 
%                 delay_log = []; % 记录传输延迟
%                 tx_count = 0;   % 记录成功传输的包数
% 
%                 while current_time < sim_time
%                     % 1. 传感器泊松发包
%                     for sid = 1:N_sensor
%                         if rand() < dt / T_gen
%                             new_pkt = [sid, current_time, priority(sid)];
% 
%                             if policy_type == 1
%                                 % FIFO 策略
%                                 gateway_queue = [gateway_queue; new_pkt];
%                                 if size(gateway_queue,1) > max_queue_len
%                                     gateway_queue(1,:) = []; % 队满丢弃最老的
%                                 end
% 
%                             elseif policy_type == 2
%                                 % Latest replacement 策略
%                                 % 修复：先判断队列是否为空
%                                 if ~isempty(gateway_queue)
%                                     gateway_queue(gateway_queue(:,1) == sid, :) = [];
%                                 end
%                                 gateway_queue = [gateway_queue; new_pkt];
%                                 if size(gateway_queue,1) > max_queue_len
%                                     gateway_queue(1,:) = []; % 队满丢弃最老的
%                                 end
% 
%                             elseif policy_type == 3
%                                 % AoI + 优先级策略
%                                 % 修复：先判断队列是否为空
%                                 if ~isempty(gateway_queue)
%                                     gateway_queue(gateway_queue(:,1) == sid, :) = [];
%                                 end
%                                 gateway_queue = [gateway_queue; new_pkt];
%                                 % 排序：先按优先级降序(3在前)，再按生成时间降序(新的在前)
%                                 gateway_queue = sortrows(gateway_queue, [-3, -2]);
%                                 if size(gateway_queue,1) > max_queue_len
%                                     gateway_queue = gateway_queue(1:max_queue_len, :); % 截断，踢掉末尾的
%                                 end
%                             end
%                         end
%                     end
% 
%                     % 2. 链路调度 (每次只发队列里的第一个包)
%                     if ~channel_busy && ~isempty(gateway_queue)
%                         tx_packet = gateway_queue(1,:);
%                         gateway_queue(1,:) = [];  % <--- 这里当队列只剩1个包时，删掉它也会变成空
%                         channel_busy = true;
%                         tx_start_time = current_time;
%                     end
% 
%                     % 3. 传输结束 + 丢包处理
%                     if channel_busy && (current_time - tx_start_time >= T_tx)
%                         channel_busy = false;
%                         if rand() > p_loss % 未丢包
%                             sid = tx_packet(1);
%                             gen_t = tx_packet(2);
%                             last_gen_recv(sid) = gen_t;
% 
%                             % 记录延迟和成功包数
%                             delay_log = [delay_log, current_time - gen_t];
%                             tx_count = tx_count + 1;
%                         end
%                         tx_packet = [];
%                     end
% 
%                     % 4. 计算并记录 AoI
%                     aoi_inst = current_time - last_gen_recv; 
%                     mean_aoi = mean(aoi_inst); % 所有传感器的平均AoI
% 
%                     % 只有在预热期之后才记录数据
%                     if current_time > warmup_time
%                         log_step = log_step + 1;
%                         log_aoi(log_step) = mean_aoi;
%                     end
% 
%                     current_time = current_time + dt;
%                 end
% 
%                 % 截取有效数据
%                 log_aoi = log_aoi(1:log_step);
% 
%                 % 存储结果
%                 meanAoi_all(p_idx, T_idx, pol_idx, seed) = mean(log_aoi);
%                 peakAoi_all(p_idx, T_idx, pol_idx, seed) = max(log_aoi);
%                 delay_all(p_idx, T_idx, pol_idx, seed) = mean(delay_log);
%                 tx_count_all(p_idx, T_idx, pol_idx, seed) = tx_count;
%             end
%         end
%         fprintf('Finished p_loss=%.1f, T_gen=%d\n',p_loss, T_gen);
%     end
% end
% 
% %% ========== 统计：均值、标准差、置信区间 ==========
% meanAoi = zeros(n_p, n_T, n_pol);
% stdAoi = zeros(n_p, n_T, n_pol);
% ciAoi = zeros(n_p, n_T, n_pol);
% 
% for p_idx = 1:n_p
%     for T_idx = 1:n_T
%         for pol_idx = 1:n_pol
%             data = squeeze(meanAoi_all(p_idx, T_idx, pol_idx, :));
%             meanAoi(p_idx,T_idx,pol_idx) = mean(data);
%             stdAoi(p_idx,T_idx,pol_idx) = std(data);
%             % 计算95%置信区间
%             ciAoi(p_idx,T_idx,pol_idx) = t_val * stdAoi(p_idx,T_idx,pol_idx)/sqrt(n_seed);
%         end
%     end
% end
% 
% %% ========== 绘图：每个丢包率一张 errorbar 图（x轴是T_gen） ==========
% color_list = {'r','g','b'};
% marker_list = {'o','s','^'};
% 
% for p_idx = 1:n_p
%     figure('Color','w', 'Position', [100+p_idx*100, 100, 600, 400]);
%     hold on; grid on;
%     for pol_idx = 1:n_pol
%         x = T_gen_list;
%         y = meanAoi(p_idx,:,pol_idx);
%         err = ciAoi(p_idx,:,pol_idx);
%         errorbar(x, y, err, [color_list{pol_idx}], ...
%             'Marker',marker_list{pol_idx},'LineWidth',1.5, 'MarkerSize', 8);
%     end
%     xlabel('Packet Generation Interval T_{gen} (s)', 'FontSize', 12);
%     ylabel('Mean AoI (s)', 'FontSize', 12);
%     title(['Mean AoI under Loss rate = ',num2str(p_loss_list(p_idx))], 'FontSize', 14);
%     legend(policy_name,'Location','best', 'FontSize', 11);
%     hold off;
% end
% 
% %% ========== 输出表格到命令行，方便复制进报告 ==========
% fprintf('\n==== Mean AoI Table (rows:T_gen, columns:FIFO / Latest / AoI-Priority) ====\n');
% for p_idx = 1:n_p
%     fprintf('\n----- Loss = %.1f -----\n',p_loss_list(p_idx));
%     for T_idx = 1:n_T
%         fprintf('T_gen=%d: %.2f\t%.2f\t%.2f\n',...
%             T_gen_list(T_idx), meanAoi(p_idx,T_idx,1), meanAoi(p_idx,T_idx,2), meanAoi(p_idx,T_idx,3));
%     end
% end
% 
% % 补充打印 Delivery Delay 和 Transmitted Packets 的均值（用于写报告）
% fprintf('\n==== Average Delivery Delay & Tx Packets (Loss = 0.1) ====\n');
% fprintf('T_gen\tFIFO_Delay\tLatest_Delay\tAoI_Delay\n');
% for T_idx = 1:n_T
%     fprintf('%d\t%.2f\t\t%.2f\t\t%.2f\n', T_gen_list(T_idx), ...
%         mean(squeeze(delay_all(2, T_idx, 1, :))), ...
%         mean(squeeze(delay_all(2, T_idx, 2, :))), ...
%         mean(squeeze(delay_all(2, T_idx, 3, :))));
% end