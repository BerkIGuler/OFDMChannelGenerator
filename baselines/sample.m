% Parameters and setup for LMMSE
lmmse_stats_dataset = "train_N7"; % Dataset for LMMSE correlation statistics
parent_dir = fileparts(fileparts(fileparts(pwd)));
lmmse_param_path = fullfile(parent_dir, 'datasets', lmmse_stats_dataset);

% Get LMMSE correlation statistics
[mean_R_hphp, mean_R_hhp, mean_var] = get_corr_stats_N7(lmmse_param_path);

% Set up input and output folders
input_folder = fullfile(parent_dir, 'datasets', 'sample_ds');
output_folder_ls = './LS';
output_folder_lmmse = './LMMSE';
output_folder_gt = './GT';

% Create output folders if they don't exist
if ~exist(output_folder_ls, 'dir')
    mkdir(output_folder_ls)
end
if ~exist(output_folder_lmmse, 'dir')
    mkdir(output_folder_lmmse)
end
if ~exist(output_folder_gt, 'dir')
    mkdir(output_folder_gt)
end

% Get list of .mat files in input folder
files = dir(fullfile(input_folder, '*.mat'));

% Process each file
for i = 1:length(files)
    % Load current file
    file_path = fullfile(input_folder, files(i).name);
    data = load(file_path);
    test_channels = data.H;
    
    % Extract channels
    h_ls = test_channels(:, :, 3);      % LS interpolated channel
    hp_ls = test_channels(:, :, 2);     % channel at pilot locations
    h_ideal = test_channels(:, :, 1);   % ground truth channel
    
    % Calculate LMMSE estimate
    h_lmmse = lmmse(mean_R_hphp, mean_R_hhp, mean_var, hp_ls);
    
    % Separate real and imaginary components
    % For ground truth channel
    h_ideal_real = real(h_ideal);
    h_ideal_imag = imag(h_ideal);
    h_ideal_separated = cat(1, reshape(h_ideal_real, [1, size(h_ideal_real)]), ...
                             reshape(h_ideal_imag, [1, size(h_ideal_imag)]));
    
    % For LS estimated channel
    h_ls_real = real(h_ls);
    h_ls_imag = imag(h_ls);
    h_ls_separated = cat(1, reshape(h_ls_real, [1, size(h_ls_real)]), ...
                           reshape(h_ls_imag, [1, size(h_ls_imag)]));
    
    % For LMMSE estimated channel
    h_lmmse_real = real(h_lmmse);
    h_lmmse_imag = imag(h_lmmse);
    h_lmmse_separated = cat(1, reshape(h_lmmse_real, [1, size(h_lmmse_real)]), ...
                             reshape(h_lmmse_imag, [1, size(h_lmmse_imag)]));
    
    % Generate output filenames (removing .mat extension)
    [~, base_filename, ~] = fileparts(files(i).name);
    
    % Save channels as .mat files
    % Ground truth channel
    gt_filename = fullfile(output_folder_gt, [base_filename '_gt.mat']);
    H = h_ideal_separated;
    save(gt_filename, 'H');
    
    % LS estimated channel
    ls_filename = fullfile(output_folder_ls, [base_filename '_ls.mat']);
    H = h_ls_separated;
    save(ls_filename, 'H');
    
    % LMMSE estimated channel
    lmmse_filename = fullfile(output_folder_lmmse, [base_filename '_lmmse.mat']);
    H = h_lmmse_separated;
    save(lmmse_filename, 'H');
    
    fprintf('Processed file %d/%d: %s\n', i, length(files), files(i).name);
end

fprintf('\nProcessing complete. Files saved in:\n');
fprintf('1. LS estimates: %s\n', output_folder_ls);
fprintf('2. LMMSE estimates: %s\n', output_folder_lmmse);
fprintf('3. Ground truth: %s\n', output_folder_gt);