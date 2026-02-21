function [mean_R_hphp, mean_R_hhp, mean_var] = get_corr_stats(path_to_folder)
    % Estimate E[R_hphp], E[R_hhp], E[noise_var] via sample mean over a folder.
    %
    %   Input:
    %       path_to_folder - Folder containing .mat channel samples
    %
    %   Output:
    %       mean_R_hphp - Sample mean of auto-correlation R_hphp (Np x Np)
    %       mean_R_hhp  - Sample mean of cross-correlation R_hhp  (K x Np)
    %       mean_var    - Sample mean of noise variance (scalar)

    files = dir(fullfile(path_to_folder, '*.mat'));

    % Initialize from first sample to avoid hardcoded dimensions
    [R_hhp, R_hphp, noise_var] = get_corr_from_path(fullfile(path_to_folder, files(1).name));
    mean_R_hphp = R_hphp;
    mean_R_hhp = R_hhp;
    mean_var = noise_var;

    % Running sample mean for remaining files
    for j = 2:length(files)
        file_path = fullfile(path_to_folder, files(j).name);
        [R_hhp, R_hphp, noise_var] = get_corr_from_path(file_path);

        w = 1 / j;
        mean_R_hphp = mean_R_hphp * (1 - w) + R_hphp * w;
        mean_R_hhp  = mean_R_hhp  * (1 - w) + R_hhp  * w;
        mean_var    = mean_var    * (1 - w) + noise_var * w;
    end
end
