%% Linear interpolation to estimate missing elements in a matrix
% Author: Berkay Guler
% Date: 19.11.2025

function H_hat = bilinear_interp(H_ls)
    % H_ls: input matrix with missing entries set to 0
    % H_hat: matrix where missing entries are interpolated linearly from the known ones.
    [n_row, n_col] = size(H_ls);
    % Interpolate along rows first
    for i = 1:n_row
        curr_row = H_ls(i, :);
        nonzero_inds = find(curr_row);
        % Continue if we have a row of zeros
        try
            new_row = interp1(nonzero_inds, curr_row(nonzero_inds), ...
                1:1:n_col, "linear", "extrap");
            H_ls(i, :) = new_row;
        catch
            continue
        end
    end
    % Interpolate along columns
    for i = 1:n_col
        curr_col = H_ls(:, i);
        nonzero_inds = find(curr_col);
        % Continue if we have a column of zeros
        try
            new_col = interp1(nonzero_inds, curr_col(nonzero_inds), ...
                1:1:n_row, "linear", "extrap");
            H_ls(:, i) = new_col;
        catch
            continue
        end
    end
    H_hat = H_ls;
end
