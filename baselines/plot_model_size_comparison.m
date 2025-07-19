%% Reports baseline CE algorithms' Performance
param_to_unit = dictionary (["SNR" "Max. Doppler Shift" "Delay Spread"], ["dB", "Hz", "ns"]);
N = 6; % Adjust this value to control the number of data points to plot
varying_param = "SNR"; % MUST BE ONE OF SNR, MDS, OR DS
parent_dir = fileparts(fileparts(fileparts(pwd)));
adafortitranM_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranM_large.csv"));
adafortitranS_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranS_large.csv"));
adafortitranL_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranL_large.csv"));
adafortitranXL_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_AdaFortiTranXL_large.csv"));
fortitran_results_path = fullfile(parent_dir, "python_results", strcat(varying_param, "_FortiTran_large.csv"));
%% read python results from disk
adafortitranS_table = readtable(adafortitranS_results_path);
adafortitranM_table = readtable(adafortitranM_results_path);
adafortitranL_table = readtable(adafortitranL_results_path);
adafortitranXL_table = readtable(adafortitranXL_results_path);
fortitran_table = readtable(fortitran_results_path);
%% plot
figure(1);
plot(fortitran_table.Step(1:N), fortitran_table.Value(1:N), '--+', 'LineWidth', 2, 'Color', [0 0 0]); % FortiTran (Black) - Dashed
hold on;
plot(adafortitranS_table.Step(1:N), adafortitranS_table.Value(1:N), ':d', 'LineWidth', 2, 'Color', [1 0 0]); % AdaFortiTranS (Pure Red) - Dotted
plot(adafortitranM_table.Step(1:N), adafortitranM_table.Value(1:N), '-p', 'LineWidth', 2, 'Color', [0 0.5 0]); % AdaFortiTranM (Dark Green) - Solid
plot(adafortitranL_table.Step(1:N), adafortitranL_table.Value(1:N), '-.^', 'LineWidth', 2, 'Color', [0 0 1]); % AdaFortiTranL (Pure Blue) - Dash-dot
plot(adafortitranXL_table.Step(1:N), adafortitranXL_table.Value(1:N), '-.^', 'LineWidth', 2, 'Color', [0.5 0 0.5]); % AdaFortiTranXL (Purple) - Dash-dot
grid on;
xlabel(sprintf('%s (%s)', "SNR", param_to_unit("SNR")), 'FontWeight', 'bold');
ylabel("MSE (dB)", 'FontWeight', 'bold');
legend('FortiTranL (L=3)', 'AdaFortiTranS (L=1)', 'AdaFortiTranM (L=3)', 'AdaFortiTranL (L=6)', 'AdaFortiTranXL (L=12)');
ylim([-50, -25]); % Replace y_min and y_max with your desired values
% Make axes and tick labels bold
set(gca, 'FontWeight', 'bold');