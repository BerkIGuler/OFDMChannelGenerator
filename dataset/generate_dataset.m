% Author: Berkay Guler
% Date: 08.06.2000

% Generates a dataset of OFDM channels with given characteristics 
% including SNR, delay spread, max. Doppler shift, and delay profile

% Add the path where the required functions are located
[parent_dir, ~, ~] = fileparts(pwd);
addpath(fullfile(parent_dir, 'functions'));

N = 4;
folder_name = "val_large_N4";
num_channels = 10000;

sample_rate = 3.84e6;

SNR = 0:5:25;
delay_spread = 25:25:300;
max_dop_shift = 50:50:1000;
delay_profile = "TDL-A";

if ~exist(folder_name, 'dir')
   mkdir(folder_name)
end

report_every_n = 1000;

f = waitbar(0, 'Starting');

for i = 1:num_channels
    random_idx = randi(length(SNR), 1);
    curr_SNR = SNR(random_idx);

    random_idx = randi(length(delay_spread), 1);
    curr_delay_spread = delay_spread(random_idx);
    
    random_idx = randi(length(max_dop_shift), 1);
    curr_doppler_shift = max_dop_shift(random_idx);

    [H_ideal, H_ls, H_ls_interp, tx_grid, var_hat] = generate_pair(curr_SNR, ...
        curr_delay_spread * 1e-9, curr_doppler_shift, ...
        delay_profile, sample_rate, N);
    
    H = cat(3, H_ideal, H_ls, H_ls_interp, tx_grid);
    
    file_name = strcat(int2str(i), "_", ...
        "SNR-", int2str(curr_SNR), "_", ...
        "DS-", int2str(curr_delay_spread), "_", ...
        "DOP-", int2str(curr_doppler_shift), "_", ...
        "N-", int2str(N), "_", ...
        delay_profile);
    save_path = fullfile(folder_name, file_name);
    save(save_path, "H", "var_hat")
    
    if mod(i, report_every_n) == 0
        waitbar(i / num_channels, f, sprintf('Progress: %d %%', ...
            floor((i / num_channels) * 100)));
    end   
end

close(f)
