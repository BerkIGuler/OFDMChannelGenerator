function [R_hhp, R_hphp, noise_var] = get_corr_from_path(path)
    % Compute correlation matrices and noise variance from a saved sample.
    %
    %   Input:
    %       path - Path to .mat file containing H (num_sc x num_sym x 2)
    %              and noise_var (scalar)
    %
    %   Output:
    %       R_hhp     - Cross-correlation h * hp' (K x Np)
    %       R_hphp    - Auto-correlation hp * hp' (Np x Np)
    %       noise_var - Noise variance per complex element

    data = load(path);
    channels = data.H;

    h = channels(:, :, 1);
    h = h(:);

    hp = channels(:, :, 2);
    hp = hp(hp ~= 0);

    R_hhp = h * hp';
    R_hphp = hp * hp';
    noise_var = data.noise_var;
end
