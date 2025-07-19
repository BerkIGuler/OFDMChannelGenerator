parent_dir = fileparts(fileparts(fileparts(pwd)));
results_path = fullfile(parent_dir, "python_results", 'pilot_density_large_snr5.csv');

% Read the CSV file
data = readtable(results_path);

% Select only the desired N values (15, 20, 24, 30)
selected_indices = ismember(data.N, [15, 20, 24, 30]);
data = data(selected_indices, :);

% Sort data by N in ascending order
[sorted_N, idx] = sort(data.N, 'ascend');
data = data(idx,:);

% Create x-axis labels
x_values = data.N;
x_labels = cellstr(strcat('(', string(data.N), '×2', ')')); 

% Create plot
figure(1);
plot(x_values, data.sis, '-p', 'LineWidth', 2, 'Color', [0.5 0.5 0]); % SisRaFNet (Olive) - Solid
hold on;
plot(x_values, data.cevit, ':d', 'LineWidth', 2, 'Color', [0 0.5 0]); % CeViT (Green) - Dotted
plot(x_values, data.ada, '-.^', 'LineWidth', 2, 'Color', [0.5 0 0.5]); % AdaFortiTran (Purple) - Dash-dot
plot(x_values, data.forti, '--o', 'LineWidth', 2, 'Color', [1 0 0]); % FortiTran (Red) - Dashed

grid on;
xlabel('Pilot Matrix Size', 'FontWeight', 'bold');
ylabel('MSE (dB)', 'FontWeight', 'bold');
legend('SisRaFNet', 'CeViT', 'AdaFortiTranL', 'FortiTranM');

% Adjust y-axis limits based on data range
ylim([-41 -33]); % Modified to focus on the range of all methods
xlim([14 31]); % Modified to fit the selected N values

% Set x-axis ticks and labels
set(gca, 'XTick', x_values);
set(gca, 'XTickLabel', x_labels);

% Make axes bold
set(gca, 'FontWeight', 'bold');