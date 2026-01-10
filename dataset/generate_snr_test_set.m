% Author: Berkay Guler
% Date: 19.11.2025

% Generates OFDM channel pairs with given characteristics 
% including fixed max. dopp. shift, delay spread, delay profile,
% and varying SNR

% Add the path where the required functions are located to the MATLAB path
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

delay_profile = "TDL-A"; % delay profile to use in generating the channel
N = 3; % insert pilots every N subcarriers
delay_spread = 200; % delay spread to use in generating the channel in ns
max_doppler_shift = 500; % max. Doppler shift to use in generating the channel in Hz
SNR = 0: 5: 25; % array of SNR values to use in generating the channel in dB
sample_rate = 3.84e6; % sample rate of the OFDM signal
folder_name = "test/SNR_test_set"; % folder name to save the dataset

if ~exist(folder_name, 'dir') % create the folder if it doesn't exist
   mkdir(folder_name)
end

num_samples_per_SNR = 2000; % number of samples per SNR value

% Create the OFDM channel estimator instance
estimator = OFDMChannelEstimator();

f = waitbar(0, 'Starting'); % create a waitbar to show the progress

total_samples = length(SNR) * num_samples_per_SNR; % total number of samples to save
sample_count_so_far = 0;
report_every_n_samples = 100; % report progress every n samples

for i = 1:length(SNR)
    curr_SNR = SNR(i); % set the current SNR value
    for j = 1:num_samples_per_SNR
    
        % generate the channel pair using the estimator
        [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = estimator.estimate( ...
            curr_SNR, delay_spread, max_doppler_shift, ...
            delay_profile, sample_rate, N);
        
        H = cat(3, H_ideal, H_ls);
        
        file_name = strcat(int2str(j), "_", ...
            "SNR-", int2str(curr_SNR), "_", ...
            "DS-", int2str(delay_spread), "_", ...
            "DOP-", int2str(max_doppler_shift), "_", ...
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
