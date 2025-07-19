function [h_lmmse] = lmmse(R_hphp, R_hhp, noise_var, hp_ls)
    % Based on the formula in:
        % F. Liu, J. Zhang, P. Jiang, C. -K. Wen and S. Jin, 
        % "CE-ViT: A Robust Channel Estimator Based on Vision Transformer 
        % for OFDM Systems," GLOBECOM 2023 - 2023 IEEE Global Communications
        % Conference, Kuala Lumpur, Malaysia, 2023, pp. 4798-4803
    
    diagonal_variance = eye(size(R_hphp, 1)) * noise_var;
    % take only nonzero elements
    hp_ls = hp_ls(hp_ls ~= 0 + 0i);
    
    % h_lmmse = R_hhp * inv(R_hphp + diagonal_variance) * hp_ls;
    % / is a more efficient way to take inverse
    inv_hp_ls = (R_hphp + diagonal_variance) \ hp_ls;
    h_lmmse = R_hhp * inv_hp_ls;
    h_lmmse = reshape(h_lmmse, 120, 14);
end

