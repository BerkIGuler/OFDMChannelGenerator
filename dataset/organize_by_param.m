%% This scripts groups a dataset under subfolders.

% Specify the folder containing the files
source_folder = 'test_noisy/DS_test_set';

% Set the organize_by variable ('SNR', 'DS', or 'DOP')
organize_by = 'DS'; % Change this to 'DS' or 'DOP' as needed

% Get a list of all .mat files in the folder
files = dir(fullfile(source_folder, '*.mat'));

% Loop through each file in the folder
for i = 1:numel(files)
    % Get the full filename
    filename = files(i).name;
    
    % Extract the value based on organize_by
    value_str = regexp(filename, [organize_by '-(\d+)'], 'tokens');
    value = value_str{1}{1};
    
    % Create a new folder for the value if it doesn't exist
    destination_folder = fullfile(source_folder, [organize_by '_' value]);
    if ~exist(destination_folder, 'dir')
        mkdir(destination_folder);
    end
    
    % Copy the file to the new folder
    copyfile(fullfile(source_folder, filename), ...
        fullfile(destination_folder, filename));
    delete(fullfile(source_folder, filename));
end

disp(['Files organized by ' organize_by ' value.']);
