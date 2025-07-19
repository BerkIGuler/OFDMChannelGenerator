% Author: Berkay Guler
% Date: 08.06.2024

% generates a dataset of OFDM channels
% with fixed SNR and delay spread, delay profile,
% and varying mds

% add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

delay_spread = 200;
delay_profile = "TDL-A";
N = 7;
SNR = 20;
max_dop_shift = 200:200:1000;
sample_rate = 3.84e6;
folder_name = "test_noisy/MDS_test_set";

if ~exist(folder_name, 'dir')
   mkdir(folder_name)
end

num_samples_per_mds = 2000;

f = waitbar(0, 'Starting');

total_samples = length(max_dop_shift) * num_samples_per_mds;
sample_count_so_far = 0;
report_every_n_samples = 10;

std_dev = 200;  % Define the standard deviation for the Gaussian noise

for i = 1:length(max_dop_shift)
    for j = 1:num_samples_per_mds
        curr_mds = max_dop_shift(i);
        
        % Generate Gaussian noise with standard deviation 40
        gaussian_noise = std_dev * randn;  % Zero mean, standard deviation 40
        noisy_mds = max(curr_mds + gaussian_noise, 0);
    
        [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = generate_pair( ...
            SNR, delay_spread * 1e-9, noisy_mds, ...  % Use noisy mds in the computation
            delay_profile, sample_rate, N);
        
        H = cat(3, H_ideal, H_ls, H_ls_interp, tx_grid);
        
        % Use curr_mds (without noise) in the file name
        file_name = strcat(int2str(j), "_", ...
            "SNR-", int2str(SNR), "_", ...
            "DS-", int2str(delay_spread), "_", ...
            "DOP-", int2str(curr_mds), "_", ... % Use original curr_mds here
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
