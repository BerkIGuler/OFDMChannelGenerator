% Author: Berkay Guler
% Date: 01.10.2026
%
% GENERATE_FULL_DATASET - Master script to generate complete dataset for paper replication
%
% This script generates:
%   1. Training set (100k samples)
%   2. Validation set (10k samples)
%   3. SNR test set (organized by SNR)
%   4. Delay Spread test set (organized by DS)
%   5. Max Doppler Shift test set (organized by MDS)
%
% All parameters match those used in the AdaFortiTran paper.

clc;
clear;
close all;

% Add helpers to MATLAB path
addpath('helpers');

%% ========== CONFIGURATION ==========

% Common parameters
N = 3;                          % Pilot spacing
sample_rate = 3.84e6;           % Sample rate (Hz)
delay_profile = "TDL-A";        % Channel delay profile

% Training/Validation parameters (randomly sampled from these ranges)
SNR_range = 0:5:25;             % SNR values (dB)
delay_spread_range = 25:25:300; % Delay spread values (ns)
max_dop_shift_range = 50:50:1000; % Max Doppler shift values (Hz)

% Dataset sizes
train_size = 100000;            % Training samples
val_size = 10000;               % Validation samples

% Test set parameters
test_samples_per_value = 2000;  % Samples per parameter value

% SNR test set (fixed DS and MDS, varying SNR)
snr_test_delay_spread = 200;    % Fixed delay spread (ns)
snr_test_max_doppler = 500;     % Fixed max Doppler shift (Hz)
snr_test_values = 0:5:25;       % SNR values to test (dB)

% Delay Spread test set (fixed SNR and MDS, varying DS)
ds_test_snr = 10;               % Fixed SNR (dB)
ds_test_max_doppler = 600;      % Fixed max Doppler shift (Hz)
ds_test_values = 50:50:300;     % Delay spread values to test (ns)

% Max Doppler Shift test set (fixed SNR and DS, varying MDS)
mds_test_snr = 10;              % Fixed SNR (dB)
mds_test_delay_spread = 100;    % Fixed delay spread (ns)
mds_test_values = 200:200:1000; % Max Doppler shift values to test (Hz)

%% ========== CREATE DIRECTORIES ==========

fprintf('=== OFDM Channel Dataset Generator ===\n\n');

folders = {'train', 'val', 'test/SNR_test_set', 'test/DS_test_set', 'test/MDS_test_set'};
for i = 1:length(folders)
    if ~exist(folders{i}, 'dir')
        mkdir(folders{i});
    end
end

%% ========== INITIALIZE ESTIMATOR ==========

fprintf('Initializing OFDMChannelEstimator...\n');
estimator = OFDMChannelEstimator(sample_rate, delay_profile, N);
fprintf('\n');

%% ========== 1. GENERATE TRAINING SET ==========

fprintf('=== Step 1/5: Generating Training Set (%d samples) ===\n', train_size);
f = waitbar(0, 'Generating training set...');

for i = 1:train_size
    curr_SNR = SNR_range(randi(length(SNR_range)));
    curr_delay_spread = delay_spread_range(randi(length(delay_spread_range)));
    curr_doppler_shift = max_dop_shift_range(randi(length(max_dop_shift_range)));
    
    [H_ideal, H_ls, ~, ~, var_hat] = estimator.estimate(curr_SNR, curr_delay_spread, curr_doppler_shift);
    H = cat(3, H_ideal, H_ls);
    
    file_name = sprintf('%d_SNR-%d_DS-%d_DOP-%d_N-%d_%s', ...
        i, curr_SNR, curr_delay_spread, curr_doppler_shift, N, delay_profile);
    save(fullfile('train', file_name), 'H', 'var_hat');
    
    if mod(i, 1000) == 0
        waitbar(i / train_size, f, sprintf('Training: %d/%d (%.0f%%)', i, train_size, 100*i/train_size));
    end
end
close(f);
fprintf('Training set complete.\n\n');

%% ========== 2. GENERATE VALIDATION SET ==========

fprintf('=== Step 2/5: Generating Validation Set (%d samples) ===\n', val_size);
f = waitbar(0, 'Generating validation set...');

for i = 1:val_size
    curr_SNR = SNR_range(randi(length(SNR_range)));
    curr_delay_spread = delay_spread_range(randi(length(delay_spread_range)));
    curr_doppler_shift = max_dop_shift_range(randi(length(max_dop_shift_range)));
    
    [H_ideal, H_ls, ~, ~, var_hat] = estimator.estimate(curr_SNR, curr_delay_spread, curr_doppler_shift);
    H = cat(3, H_ideal, H_ls);
    
    file_name = sprintf('%d_SNR-%d_DS-%d_DOP-%d_N-%d_%s', ...
        i, curr_SNR, curr_delay_spread, curr_doppler_shift, N, delay_profile);
    save(fullfile('val', file_name), 'H', 'var_hat');
    
    if mod(i, 100) == 0
        waitbar(i / val_size, f, sprintf('Validation: %d/%d (%.0f%%)', i, val_size, 100*i/val_size));
    end
end
close(f);
fprintf('Validation set complete.\n\n');

%% ========== 3. GENERATE SNR TEST SET ==========

total_snr_samples = length(snr_test_values) * test_samples_per_value;
fprintf('=== Step 3/5: Generating SNR Test Set (%d samples) ===\n', total_snr_samples);
f = waitbar(0, 'Generating SNR test set...');
count = 0;

for i = 1:length(snr_test_values)
    curr_SNR = snr_test_values(i);
    for j = 1:test_samples_per_value
        [H_ideal, H_ls, ~, ~, var_hat] = estimator.estimate(curr_SNR, snr_test_delay_spread, snr_test_max_doppler);
        H = cat(3, H_ideal, H_ls);
        
        file_name = sprintf('%d_SNR-%d_DS-%d_DOP-%d_N-%d_%s', ...
            j, curr_SNR, snr_test_delay_spread, snr_test_max_doppler, N, delay_profile);
        save(fullfile('test/SNR_test_set', file_name), 'H', 'var_hat');
        
        count = count + 1;
        if mod(count, 100) == 0
            waitbar(count / total_snr_samples, f, sprintf('SNR Test: %d/%d (%.0f%%)', count, total_snr_samples, 100*count/total_snr_samples));
        end
    end
end
close(f);
fprintf('SNR test set complete.\n\n');

%% ========== 4. GENERATE DELAY SPREAD TEST SET ==========

total_ds_samples = length(ds_test_values) * test_samples_per_value;
fprintf('=== Step 4/5: Generating Delay Spread Test Set (%d samples) ===\n', total_ds_samples);
f = waitbar(0, 'Generating DS test set...');
count = 0;

for i = 1:length(ds_test_values)
    curr_ds = ds_test_values(i);
    for j = 1:test_samples_per_value
        [H_ideal, H_ls, ~, ~, var_hat] = estimator.estimate(ds_test_snr, curr_ds, ds_test_max_doppler);
        H = cat(3, H_ideal, H_ls);
        
        file_name = sprintf('%d_SNR-%d_DS-%d_DOP-%d_N-%d_%s', ...
            j, ds_test_snr, curr_ds, ds_test_max_doppler, N, delay_profile);
        save(fullfile('test/DS_test_set', file_name), 'H', 'var_hat');
        
        count = count + 1;
        if mod(count, 100) == 0
            waitbar(count / total_ds_samples, f, sprintf('DS Test: %d/%d (%.0f%%)', count, total_ds_samples, 100*count/total_ds_samples));
        end
    end
end
close(f);
fprintf('Delay Spread test set complete.\n\n');

%% ========== 5. GENERATE MAX DOPPLER SHIFT TEST SET ==========

total_mds_samples = length(mds_test_values) * test_samples_per_value;
fprintf('=== Step 5/5: Generating Max Doppler Shift Test Set (%d samples) ===\n', total_mds_samples);
f = waitbar(0, 'Generating MDS test set...');
count = 0;

for i = 1:length(mds_test_values)
    curr_mds = mds_test_values(i);
    for j = 1:test_samples_per_value
        [H_ideal, H_ls, ~, ~, var_hat] = estimator.estimate(mds_test_snr, mds_test_delay_spread, curr_mds);
        H = cat(3, H_ideal, H_ls);
        
        file_name = sprintf('%d_SNR-%d_DS-%d_DOP-%d_N-%d_%s', ...
            j, mds_test_snr, mds_test_delay_spread, curr_mds, N, delay_profile);
        save(fullfile('test/MDS_test_set', file_name), 'H', 'var_hat');
        
        count = count + 1;
        if mod(count, 100) == 0
            waitbar(count / total_mds_samples, f, sprintf('MDS Test: %d/%d (%.0f%%)', count, total_mds_samples, 100*count/total_mds_samples));
        end
    end
end
close(f);
fprintf('Max Doppler Shift test set complete.\n\n');

%% ========== 6. ORGANIZE TEST SETS BY PARAMETER ==========

fprintf('=== Organizing Test Sets ===\n');

% Organize SNR test set by SNR
fprintf('Organizing SNR test set by SNR...\n');
organize_dataset('test/SNR_test_set', 'SNR');

% Organize DS test set by DS
fprintf('Organizing DS test set by DS...\n');
organize_dataset('test/DS_test_set', 'DS');

% Organize MDS test set by DOP
fprintf('Organizing MDS test set by DOP...\n');
organize_dataset('test/MDS_test_set', 'DOP');

fprintf('\n=== Dataset Generation Complete! ===\n');
fprintf('Total samples generated:\n');
fprintf('  - Training:   %d\n', train_size);
fprintf('  - Validation: %d\n', val_size);
fprintf('  - SNR Test:   %d\n', total_snr_samples);
fprintf('  - DS Test:    %d\n', total_ds_samples);
fprintf('  - MDS Test:   %d\n', total_mds_samples);
fprintf('  - TOTAL:      %d\n', train_size + val_size + total_snr_samples + total_ds_samples + total_mds_samples);

%% ========== HELPER FUNCTION ==========

function organize_dataset(source_folder, organize_by)
    % Organize dataset files into subfolders by parameter value
    files = dir(fullfile(source_folder, '*.mat'));
    
    for i = 1:numel(files)
        filename = files(i).name;
        value_str = regexp(filename, [organize_by '-(\d+)'], 'tokens');
        value = value_str{1}{1};
        
        destination_folder = fullfile(source_folder, [organize_by '_' value]);
        if ~exist(destination_folder, 'dir')
            mkdir(destination_folder);
        end
        
        movefile(fullfile(source_folder, filename), fullfile(destination_folder, filename));
    end
    
    fprintf('  Organized %d files by %s.\n', numel(files), organize_by);
end
