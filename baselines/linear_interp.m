function H_hat = linear_interp(Hp_LS)
    % Linear interpolation baseline for channel estimation.
    % Interpolates first along rows (time), then along columns (frequency).
    %
    %   Input:
    %       Hp_LS - Sparse LS channel estimate (num_subcarriers x num_symbols)
    %              Non-zero only at pilot locations
    %
    %   Output:
    %       H_hat - Interpolated channel estimate over full grid
    %              Same size as Hp_LS

    [n_row, n_col] = size(Hp_LS);
    H_hat = Hp_LS;

    % Interpolate along rows (time direction) for each subcarrier
    for i = 1:n_row
        known = find(H_hat(i, :));
        if length(known) < 2
            continue
        end
        H_hat(i, :) = interp1(known, H_hat(i, known), 1:n_col, 'linear', 'extrap');
    end

    % Interpolate along columns (frequency direction) for each OFDM symbol
    for i = 1:n_col
        known = find(H_hat(:, i));
        if length(known) < 2
            continue
        end
        H_hat(:, i) = interp1(known, H_hat(known, i), (1:n_row)', 'linear', 'extrap');
    end
end
