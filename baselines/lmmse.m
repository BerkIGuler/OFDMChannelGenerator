function H_hat = lmmse(R_hphp, R_hhp, noise_var, Hp_LS, grid_size)
    % LMMSE channel estimation baseline.
    %
    %   H_hat = R_hhp * (R_hphp + sigma^2 I)^{-1} * hp_ls
    %
    %   Reference:
    %       F. Liu, J. Zhang, P. Jiang, C.-K. Wen and S. Jin,
    %       "CE-ViT: A Robust Channel Estimator Based on Vision Transformer
    %       for OFDM Systems," GLOBECOM 2023, pp. 4798-4803
    %
    %   Input:
    %       R_hphp    - Auto-correlation of LS pilots (Np x Np)
    %       R_hhp     - Cross-correlation of full channel with LS pilots (K x Np)
    %       noise_var - Noise variance per complex element (scalar)
    %       Hp_LS     - Sparse LS channel estimate (num_subcarriers x num_symbols)
    %       grid_size - [num_subcarriers, num_symbols] for reshaping output
    %
    %   Output:
    %       H_hat     - LMMSE channel estimate (num_subcarriers x num_symbols)

    hp_ls = Hp_LS(Hp_LS ~= 0);

    H_hat = R_hhp * ((R_hphp + noise_var * eye(size(R_hphp, 1))) \ hp_ls);
    H_hat = reshape(H_hat, grid_size(1), grid_size(2));
end

