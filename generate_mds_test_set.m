% Author: Berkay Guler
% Date: 01.10.2026

% Generates OFDM channel pairs with given characteristics 
% including fixed SNR, delay spread, delay profile,
% and varying max. Doppler shift

% Add helpers to MATLAB path
addpath('helpers');

delay_profile = "TDL-A"; % delay profile to use in generating the channel
N = 3; % insert pilots every N subcarriers
SNR = 10; % SNR to use in generating the channel in dB
delay_spread = 100; % delay spread to use in generating the channel in ns
max_dop_shift = 200:200:1000; % array of max. Doppler shift values to use in generating the channel in Hz
sample_rate = 3.84e6; % sample rate of the OFDM signal
folder_name = "test/MDS_test_set"; % folder name to save the dataset

if ~exist(folder_name, 'dir') % create the folder if it doesn't exist
   mkdir(folder_name)
end

num_samples_per_mds = 2000; % number of samples per max. Doppler shift value

% Create the OFDM channel estimator instance with configuration
estimator = OFDMChannelEstimator(sample_rate, delay_profile, N);

f = waitbar(0, 'Starting'); % create a waitbar to show the progress

total_samples = length(max_dop_shift) * num_samples_per_mds; % total number of samples to save
sample_count_so_far = 0;
report_every_n_samples = 100; % report progress every n samples

for i = 1:length(max_dop_shift)
    curr_mds = max_dop_shift(i); % set the current max. Doppler shift value
    for j = 1:num_samples_per_mds
    
        % generate the channel pair using the estimator
        [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = estimator.estimate( ...
            SNR, delay_spread, curr_mds);
        
        H = cat(3, H_ideal, H_ls);
        
        file_name = strcat(int2str(j), "_", ...
            "SNR-", int2str(SNR), "_", ...
            "DS-", int2str(delay_spread), "_", ...
            "DOP-", int2str(curr_mds), "_", ...
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
