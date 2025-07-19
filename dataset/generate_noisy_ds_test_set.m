% Author: Berkay Guler
% Date: 08.06.2024

% generates a dataset of OFDM channels
% with fixed max. dopp. shift, SNR, delay profile,
% and varying delay spread

% add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

delay_profile = "TDL-A";
N = 7;
SNR = 20;
max_dop_shift = 500;
delay_spread = 50:50:300;
sample_rate = 3.84e6;
folder_name = "test_noisy/DS_test_set";

if ~exist(folder_name, 'dir')
   mkdir(folder_name)
end

num_samples_per_ds = 2000;

f = waitbar(0, 'Starting');

total_samples = length(delay_spread) * num_samples_per_ds;
sample_count_so_far = 0;
report_every_n_samples = 10;

std_dev = 50;  % Define the standard deviation for the Gaussian noise

for i = 1:length(delay_spread)
    for j = 1:num_samples_per_ds
        curr_ds = delay_spread(i);
        
        % Generate Gaussian noise with standard deviation of 50
        gaussian_noise = std_dev * randn;  % Zero mean, standard deviation 50
        noisy_ds = max(curr_ds + gaussian_noise, 0);
    
        [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = generate_pair( ...
            SNR, noisy_ds * 1e-9, max_dop_shift, ...
            delay_profile, sample_rate, N);
        
        H = cat(3, H_ideal, H_ls, H_ls_interp, tx_grid);
        
        % Use curr_ds (without noise) in the file name
        file_name = strcat(int2str(j), "_", ...
            "SNR-", int2str(SNR), "_", ...
            "DS-", int2str(curr_ds), "_", ... % Use original curr_ds here
            "DOP-", int2str(max_dop_shift), "_", ...
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
