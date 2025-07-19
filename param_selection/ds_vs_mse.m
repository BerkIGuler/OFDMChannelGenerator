% Author: Berkay Guler
% Date: 25.04.2024
% Modified: 08.06.2024

% Demonstrates the relationship between 
% LS + bilinear channel estimation error 
% and Delay Spread of the channel

% add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

delay_spread = (50:50:400) * 1e-9;

N = 3;
snr = 20;
max_dop_shift = 500;
delay_profile = "TDL-A";
num_exps = 20;
sample_rate = 3.84e6;

mse_values = zeros(1, length(delay_spread));
for i = 1:length(delay_spread)
    ds = delay_spread(i);
    curr_mse = zeros(1, num_exps);
    for j = 1:num_exps
        [H_ideal, H_ls, H_ls_interp, ~] = generate_pair(snr, ds, ...
            max_dop_shift, delay_profile, sample_rate, N);
        mse = mean(mean(abs(H_ls_interp - H_ideal).^2));
        curr_mse(j) = mse;
    end
    mse_values(i) = mean(curr_mse);
end

figure(1);
plot(delay_spread, mse_values, '--o');
title(['MSE vs Delay Spread when SNR = ', int2str(snr), ...
    ' dB, Max. Dopp. Shift = ', int2str(max_dop_shift), ' Hz'])
xlabel("Delay Spread (s)");
ylabel("MSE");
legend('LS Channel Estimate')