% Author: Berkay Guler
% Date: 08.06.2024

% generates a dataset of OFDM channels
% with fixed Max. Dopp. shift and delay spread, delay profile,
% and varying SNR

% add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

delay_spread = 200;
max_doppler_shift = 500;
delay_profile = "TDL-A";
N = 7;
SNR = 0: 5: 25;
sample_rate = 3.84e6;
folder_name = "test_noisy/SNR_test_set";

if ~exist(folder_name, 'dir')
   mkdir(folder_name)
end

num_samples_per_SNR = 2000;

f = waitbar(0, 'Starting');

total_samples = length(SNR) * num_samples_per_SNR;
sample_count_so_far = 0;
report_every_n_samples = 10;

s = 5;  % Define the desired standard deviation for the Gaussian noise

for i = 1:length(SNR)
    for j = 1:num_samples_per_SNR
        curr_SNR = SNR(i);
        
        % Generate Gaussian noise with zero mean and standard deviation s
        gaussian_noise = s * randn;  % Zero mean, standard deviation s
        noisy_SNR = curr_SNR + gaussian_noise;
    
        [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = generate_pair( ...
            noisy_SNR, delay_spread * 1e-9, max_doppler_shift, ...
            delay_profile, sample_rate, N);
        
        H = cat(3, H_ideal, H_ls, H_ls_interp, tx_grid);
        
        % Use curr_SNR (without noise) in file name
        file_name = strcat(int2str(j), "_", ...
            "SNR-", int2str(curr_SNR), "_", ... % Use curr_SNR here
            "DS-", int2str(delay_spread), "_", ...
            "DOP-", int2str(max_doppler_shift), "_", ...
            "N-", int2str(N), "_", ...
            delay_profile);
        save_path = fullfile(folder_name, file_name);
        save(save_path, "H", "var_hat")

        if mod(sample_count_so_far, report_every_n_samples) == 0
            waitbar(sample_count_so_far / total_samples, ... 
                f, sprintf('Progress: %d %%', ...
                floor((sample_count_so_far / total_samples) * 100)));
        end
        sample_count_so_far = sample_count_so_far + 1;
    end
end


close(f)
