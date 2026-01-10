% Author: Berkay Guler
% Date: 19.11.2025

% Generates OFDM channel pairs with given characteristics 
% including fixed max. dopp. shift, SNR, delay profile,
% and varying delay spread

% Add the path where the required functions are located to the MATLAB path
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

delay_profile = "TDL-A"; % delay profile to use in generating the channel
N = 3; % insert pilots every N subcarriers
SNR = 10; % SNR to use in generating the channel in dB
max_dop_shift = 600; % max. Doppler shift to use in generating the channel in Hz
delay_spread = 50:50:300; % array of delay spread values to use in generating the channel in ns
sample_rate = 3.84e6; % sample rate of the OFDM signal
folder_name = "test/DS_test_set"; % folder name to save the dataset

if ~exist(folder_name, 'dir') % create the folder if it doesn't exist
   mkdir(folder_name)
end

num_samples_per_ds = 2000; % number of samples per delay spread value

% Create the OFDM channel estimator instance
estimator = OFDMChannelEstimator();

f = waitbar(0, 'Starting'); % create a waitbar to show the progress

total_samples = length(delay_spread) * num_samples_per_ds; % total number of samples to save
sample_count_so_far = 0;
report_every_n_samples = 100; % report progress every n samples

for i = 1:length(delay_spread)
    curr_ds = delay_spread(i); % set the current delay spread value
    for j = 1:num_samples_per_ds
    
        % generate the channel pair using the estimator
        [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = estimator.estimate( ...
            SNR, curr_ds, max_dop_shift, ...
            delay_profile, sample_rate, N);
        
        H = cat(3, H_ideal, H_ls);
        
        file_name = strcat(int2str(j), "_", ...
            "SNR-", int2str(SNR), "_", ...
            "DS-", int2str(curr_ds), "_", ...
            "DOP-", int2str(max_dop_shift), "_", ...
            "N-", int2str(N), "_", ...
            delay_profile);
        save_path = fullfile(folder_name, file_name);
        save(save_path, "H", "var_hat") % save the channel pair and the estimated noise variance
        
        if mod(sample_count_so_far, report_every_n_samples) == 0
            waitbar(sample_count_so_far / total_samples, ... % update the waitbar
                f, sprintf('Progress: %d %%', ...
                floor((sample_count_so_far / total_samples) * 100)));
        end
        sample_count_so_far = sample_count_so_far + 1;
    end
end

close(f)
