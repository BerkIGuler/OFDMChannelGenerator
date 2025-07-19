% Script to generate separate CSV files for LS and LMMSE NMSE results
% Parameters
varying_param = "DS"; % MUST BE ONE OF SNR, MDS, OR DS
lmmse_stats_dataset = "train_N7";

parent_dir = fileparts(fileparts(fileparts(pwd)));

% Setup paths - using current directory as base
test_set_path = fullfile(parent_dir , 'datasets', 'test_N7_noisy', strcat(varying_param, '_test_set'));
lmmse_param_path = fullfile(parent_dir , 'datasets', lmmse_stats_dataset);

% Get LMMSE correlation statistics
[mean_R_hphp, mean_R_hhp, mean_var] = get_corr_stats_N7(lmmse_param_path);

% Get and sort subfolders
subfolders = dir(test_set_path);
subfolders = subfolders([subfolders.isdir]);
subfolders = subfolders(~ismember({subfolders.name}, {'.', '..'}));

% Extract and sort values
values = arrayfun(@(s) str2double(extractAfter(s.name, '_')), subfolders);
[sorted_values, sort_inds] = sort(values);
sorted_subfolders = subfolders(sort_inds);

% Initialize arrays for results
lmmse_nmses = zeros(1, length(sorted_subfolders));
ls_nmses = zeros(1, length(sorted_subfolders));

% Process each subfolder
for i = 1:length(sorted_subfolders)
    test_set_subfolder_path = fullfile(test_set_path, sorted_subfolders(i).name);
    items_in_curr_subfolder = dir(test_set_subfolder_path);
    files_in_curr_subfolder = items_in_curr_subfolder(~[items_in_curr_subfolder.isdir]);
    lmmse_nmse_values = zeros(1, length(files_in_curr_subfolder));
    ls_nmse_values = zeros(1, length(files_in_curr_subfolder));
    
    % Process each file in subfolder
    for j = 1:length(files_in_curr_subfolder)
        test_file_path = fullfile(test_set_subfolder_path, files_in_curr_subfolder(j).name);
        test_file = load(test_file_path);
        test_channels = test_file.H;
        h_ls = test_channels(:, :, 3); % interpolated channel
        hp_ls = test_channels(:, :, 2); % channel at pilot locations
        h_ideal = test_channels(:, :, 1); % gt channel
        
        % Calculate LMMSE estimate
        h_lmmse = lmmse(mean_R_hphp, mean_R_hhp, mean_var, hp_ls);
        
        % Calculate NMSE for both methods
        % NMSE = E[|h_est - h_ideal|^2] / E[|h_ideal|^2]
        nmse_ls = mean(mean(abs(h_ls - h_ideal).^2)) / mean(mean(abs(h_ideal).^2));
        nmse_lmmse = mean(mean(abs(h_lmmse - h_ideal).^2)) / mean(mean(abs(h_ideal).^2));
        
        lmmse_nmse_values(j) = nmse_lmmse;
        ls_nmse_values(j) = nmse_ls;
    end
    
    % Average NMSE values for current subfolder
    lmmse_nmses(i) = mean(lmmse_nmse_values);
    ls_nmses(i) = mean(ls_nmse_values);
end

% Convert NMSE values to dB
lmmse_nmses_db = 10 * log10(lmmse_nmses);
ls_nmses_db = 10 * log10(ls_nmses);


% Ensure vectors are column vectors
sorted_values = sorted_values(:);  % Force column vector
ls_nmses_db = ls_nmses_db(:);     % Force column vector
lmmse_nmses_db = lmmse_nmses_db(:);  % Force column vector

% Create tables
ls_table = table(sorted_values, ls_nmses_db, ...
    'VariableNames', {'Step', 'Value'});
lmmse_table = table(sorted_values, lmmse_nmses_db, ...
    'VariableNames', {'Step', 'Value'});

% Save results to current directory
writetable(ls_table, strcat(varying_param, '_LS.csv'));
writetable(lmmse_table, strcat(varying_param, '_LMMSE.csv'));

% Display confirmation message
fprintf('NMSE Results have been saved to:\n');
fprintf('1. %s\n', strcat(pwd, filesep, varying_param, '_LS.csv'));
fprintf('2. %s\n', strcat(pwd, filesep, varying_param, '_LMMSE.csv'));