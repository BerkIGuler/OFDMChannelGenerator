%% Reports baseline CE algorithms' Performance

param_to_unit = dictionary (["SNR" "Max. Doppler Shift" "Delay Spread"], ["dB", "Hz", "ns"]);
N = 6; % Adjust this value to control the number of data points to plot

varying_param = "DS";  % MUST BE ONE OF SNR, MDS, OR DS
lmmse_stats_dataset = "train";  

parent_dir = fileparts(fileparts(fileparts(pwd)));

cevit_results_path = fullfile(parent_dir, "python_results",  strcat(varying_param, "_CeViT_large.csv"));
adafortitranM_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranM_large.csv"));
adafortitranS_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranS_large.csv"));
adafortitranL_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranL_large.csv"));
fortitran_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_FortiTranM_large.csv"));
linear_results_path = fullfile(parent_dir, "python_results",  strcat(varying_param, "_linear_large.csv"));
sisrafnet_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_SisRafNet_large.csv"));

lmmse_param_path = fullfile( ...
    parent_dir, 'datasets', lmmse_stats_dataset);
[mean_R_hphp, mean_R_hhp, mean_var] = get_corr_stats( ...
    lmmse_param_path);

test_set_path = fullfile( ...
    parent_dir, 'datasets', 'test', strcat(varying_param, '_test_set'));

subfolders = dir(test_set_path);
% Keep only the directories and exclude the 
% current (.) and parent (..) directories
subfolders = subfolders([subfolders.isdir]);
subfolders = subfolders(~ismember({subfolders.name}, {'.', '..'}));

% Extract integer values from the name field
values = arrayfun(@(s) str2double(extractAfter(s.name, '_')), subfolders);

% Sort struct based on the extracted integer values
[sorted_values, sort_inds] = sort(values);
sorted_subfolders = subfolders(sort_inds);

lmmse_mses = zeros(1, length(sorted_subfolders));
ls_mses = zeros(1, length(sorted_subfolders));

for i=1:length(sorted_subfolders)
    test_set_subfolder_path = fullfile(test_set_path, sorted_subfolders(i).name);
    items_in_curr_subfolder = dir(test_set_subfolder_path);    
    % Keep only the files
    files_in_curr_subfolder = items_in_curr_subfolder( ...
        ~[items_in_curr_subfolder.isdir]);
   
    lmmse_mse_values = zeros(1, length(files_in_curr_subfolder));
    ls_mse_values = zeros(1, length(files_in_curr_subfolder));

    for j=1:length(files_in_curr_subfolder)
        test_file_path = fullfile( ...
            test_set_subfolder_path, files_in_curr_subfolder(j).name);
        test_file = load(test_file_path);
        test_channels = test_file.H;
        h_ls = test_channels(:, :, 3);  % interpolated channel
        hp_ls = test_channels(:, :, 2);  % channel at pilot locations
        h_ideal = test_channels(:, :, 1);  % gt channel
        h_lmmse = lmmse(mean_R_hphp, mean_R_hhp, mean_var, hp_ls);
        mse_ls = mean(mean(abs(h_ls - h_ideal).^2));
        mse_lmmse = mean(mean(abs(h_lmmse - h_ideal).^2));

        lmmse_mse_values(j) = mse_lmmse;
        ls_mse_values(j) = mse_ls;
    end
    lmmse_mses(i) = mean(lmmse_mse_values);
    ls_mses(i) = mean(ls_mse_values);
end

%% read python results from disk
cevit_table = readtable(cevit_results_path);
adafortitranS_table = readtable(adafortitranS_results_path);
adafortitranM_table = readtable(adafortitranM_results_path);
adafortitranL_table = readtable(adafortitranL_results_path);
fortitran_table = readtable(fortitran_results_path);
sisrafnet_table = readtable(sisrafnet_results_path);
linear_table = readtable(linear_results_path);


%% plot
figure(1);
% Define maximally distinguishable colors
gray = [0.50, 0.50, 0.50]; % Gray for LS
lightblue = [0.30, 0.75, 0.93]; % Light Blue for LMMSE
purple = [0.68, 0.15, 0.67]; % Vibrant Purple for AdaFortiTran
orange = [0.95, 0.45, 0.10]; % Bright Orange for FortiTran
green = [0.13, 0.70, 0.15]; % Vivid Green for CeViT
blue = [0.07, 0.10, 1.00]; % Deep Blue for SisRafNet
cyan = [0.00, 0.70, 0.70]; % Cyan for Linear

plot(sorted_values(1:N), 10*log10(ls_mses(1:N)), '-o', 'LineWidth', 2, 'Color', gray);
hold on;
plot(sorted_values(1:N), 10*log10(lmmse_mses(1:N)), '--s', 'LineWidth', 2, 'Color', lightblue);
plot(cevit_table.Step(1:N), cevit_table.Value(1:N), ':d', 'LineWidth', 2, 'Color', green);
plot(adafortitranL_table.Step(1:N), adafortitranL_table.Value(1:N), '-.^', 'LineWidth', 2, 'Color', purple);
plot(fortitran_table.Step(1:N), fortitran_table.Value(1:N), ':*', 'LineWidth', 2, 'Color', orange);
plot(sisrafnet_table.Step(1:N), sisrafnet_table.Value(1:N), '-p', 'LineWidth', 2, 'Color', blue);
plot(linear_table.Step(1:N), linear_table.Value(1:N), '--+', 'LineWidth', 2, 'Color', cyan);
grid on;

% Bold axis labels
xlabel(sprintf('%s (%s)', "Delay Spread", param_to_unit("Delay Spread")), 'FontWeight', 'bold');
ylabel("MSE (dB)", 'FontWeight', 'bold');
legend('LS + Bi-Interp.', 'LMMSE', 'CeViT', 'AdaFortiTranL', 'FortiTranM', 'SisRaFNet', 'Linear Model');
ylim([-50, 0]);

% Make axis values bold
ax = gca;
ax.FontWeight = 'bold';
% Optional: increase font size if needed
ax.FontSize = 12;
