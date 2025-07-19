function [sm_R_hphp, sm_R_hhp, sm_var] = get_corr_stats(path_to_folder)
    %% Calculates correlation and noise variance statistics of given folder
    % path_to_folder: folder containing channel data in .mat files
        
    % mean_R_hphp: mean of R_hphp matrix for given folder
    % mean_R_hhp: mean of R_hhp matrix for given folder
    % mean_var: value of noise variance for given folder

    files = dir(fullfile(path_to_folder, '*'));
    files = files(~[files.isdir]);  % Keep only files
    % sample mean as the estimate of expectation
    % sm: sample mean
    sm_var = 0;  
    sm_R_hphp = zeros(80, 80);
    sm_R_hhp = zeros(1680, 80);

    % Loop through each file and read it
    for j = 0:(length(files)-1)
        file_path = fullfile(path_to_folder, files(j+1).name);
        
        [R_hhp, R_hphp, noise_var] = get_corr_from_path(file_path);
        sm_var = (j / (j + 1)) * sm_var + (noise_var / (j + 1));
        sm_R_hphp = (j / (j + 1)) * sm_R_hphp + (R_hphp / (j + 1));
        sm_R_hhp = (j / (j + 1)) * sm_R_hhp + (R_hhp / (j + 1)); 
    end
end
