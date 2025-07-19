% Author: Berkay Guler
% Date: 25.04.2024
% Modified: 08.06.2024

% Demonstrates the relationship between 
% LS + bilinear channel estimation error 
% and SNR of the channel

% add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

SNR = 0:5:30;
N = 3;
sample_rate = 3.84e6;  % for SCS = 15 KHz
delay_spread = 200;
max_dop_shift = 500;
delay_profile = "TDL-A";

num_exps = 20;

mse_values = zeros(1, length(SNR));
for i = 1:length(SNR)
    snr = SNR(i);
    mse_for_curr_snr = zeros(1, num_exps);
    for j = 1:num_exps
        [H_ideal, H_ls, H_ls_interp, ~] = generate_pair( ...
            snr, delay_spread*1e-9, max_dop_shift, ...
            delay_profile, sample_rate, N);
        mse = mean(mean(abs(H_ls_interp - H_ideal).^2));
        mse_for_curr_snr(j) = mse;
    end
    mse_values(i) = mean(mse_for_curr_snr);
end

figure(1);
plot(SNR, mse_values, '--o');
title(['MSE vs SNR when Delay Spread = ', int2str(delay_spread), ...
    ' ns, Max. Dopp. Shift = ', int2str(max_dop_shift), ' Hz'])
xlabel("SNR (dB)");
ylabel("MSE");
legend('LS Channel Estimate')