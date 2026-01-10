% Author: Berkay Guler
% Date: 19.11.2025

% Generates OFDM channel pairs with given characteristics 
% including SNR, delay spread, max. Doppler shift, and delay profile

% Add the pathclc
%  where the required functions are located to the MATLAB path
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

N = 3; % insert pilots every N subcarriers
val_folder_name = "val";
train_folder_name = "train";
val_num_channels = 100; % number of channel pairs to generate
train_num_channels = 1000;
total_num_channels = val_num_channels + train_num_channels;

sample_rate = 3.84e6; % sample rate of the OFDM signal

SNR = 0:5:25; % array of SNR values to use in generating the channel in dB
delay_spread = 25:25:300; % array of delay spread values to use in generating the channel in ns
max_dop_shift = 50:50:1000; % max. Doppler shift values to use in generating the channel in Hz
delay_profile = "TDL-A"; % delay profile to use in generating the channel

% Create the folder if it doesn't exist
if ~exist(val_folder_name, 'dir')
   mkdir(val_folder_name)
end

if ~exist(train_folder_name, 'dir')
   mkdir(train_folder_name)
end

report_every_n = val_num_channels / 10; % report progress every n channels

% Create the OFDM channel estimator instance
estimator = OFDMChannelEstimator();

f = waitbar(0, 'Starting'); % create a waitbar to show the progress

for i = 1:total_num_channels
    random_idx = randi(length(SNR), 1); % randomly select an SNR value
    curr_SNR = SNR(random_idx); % set the current SNR value

    random_idx = randi(length(delay_spread), 1); % randomly select a delay spread value
    curr_delay_spread = delay_spread(random_idx); % set the current delay spread value
    
    random_idx = randi(length(max_dop_shift), 1); % randomly select a max. Doppler shift value
    curr_doppler_shift = max_dop_shift(random_idx);

    % generate the channel pair using the estimator
    [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = estimator.estimate(curr_SNR, ...
        curr_delay_spread, curr_doppler_shift, ...
        delay_profile, sample_rate, N);
    
    H = cat(3, H_ideal, H_ls);
    
    file_name = strcat(int2str(i), "_", ...
        "SNR-", int2str(curr_SNR), "_", ...
        "DS-", int2str(curr_delay_spread), "_", ...
        "DOP-", int2str(curr_doppler_shift), "_", ...
        "N-", int2str(N), "_", ...
        delay_profile);
    
    if i <= train_num_channels
        save_path = fullfile(train_folder_name, file_name);
    else
        save_path = fullfile(val_folder_name, file_name);
    end

    save(save_path, "H", "var_hat") % save the channel pair and the estimated noise variance

    if mod(i, report_every_n) == 0
        waitbar(i / total_num_channels, f, sprintf('Progress: %d %%', ... % update the waitbar
            floor((i / total_num_channels) * 100)));
    end   
end

close(f)
