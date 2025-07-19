function [R_hhp, R_hphp, noise_var] = get_corr_from_path(path)
    % path: path to .mat file where channel data is stored

    % noise_var: noise variance
    % R_hhp: cross corr. between gt channel and ls channel at pilot positions
    % R_hphp: auto corr of ls channel at pilot positions

    data = load(path);
    channels = data.H;
    h_ideal = channels(:, :, 1);
    h_ideal = h_ideal(:);  % vectorize to compute outer product
                           % we can either vectorize across freq. or time
                           % here we do across freq
    hp_ls = channels(:, :, 2);
    hp_ls = hp_ls(hp_ls ~= 0 + 0i);
    R_hhp = h_ideal * hp_ls';
    R_hphp = hp_ls * hp_ls';
    noise_var = data.var_hat;
end
