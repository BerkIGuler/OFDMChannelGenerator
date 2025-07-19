% Author: Berkay Guler
% Date: 25.04.2024
% Modified: 08.06.2024

% Calculates the MSE error between (LS + bilinear interpolation) channel estimate and
% actual channel. 
% The variation of MSE error with the max. Doppler Shift of the channel is
% shown

% simulates the relative speed of the objects in the environment 
% with respect to the transmitter/receiver

% add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

max_dop_shift = 200:200:1600;

sample_rate = 3.84e6;  % for SCS = 15 KHz
N = 3;
snr = 20;  % in dB
delay_spread = 200;  % in ns
delay_profile = "TDL-A";  % a predefined channel model from 3GPP

num_exps = 20;  % to report average results

mse_values = zeros(1, length(max_dop_shift));
for i = 1:length(max_dop_shift)
    mds = max_dop_shift(i);
    curr_mse = zeros(1, num_exps);
    for j = 1:num_exps
        [H_ideal, H_ls, H_ls_interp, ~] = generate_pair(snr, ...
            delay_spread*1e-9, mds, delay_profile, sample_rate, N);
        mse = mean(mean(abs(H_ls_interp - H_ideal).^2));
        curr_mse(j) = mse;
    end
    mse_values(i) = mean(curr_mse);
end

figure(1);
plot(max_dop_shift, mse_values, '--o');
title(['MSE vs Max. Doppler Shift when SNR = ', int2str(snr), ...
    ' dB, Delay Spread = ', int2str(delay_spread), 'ns'])
xlabel("Max. Doppler Shift (Hz)");
ylabel("MSE");
legend('LS Channel Estimate')
