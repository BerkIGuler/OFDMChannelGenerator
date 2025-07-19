%% Linear interpolation to estimate missing elements in a matrix
% Author: Berkay Guler
% Date: 25.04.2024
% Modified: 07.31.2024

function H_hat = bilinear_interp(H_ls)
    % H_ls: input matrix with missing entries set to 0
    % H_hat: matrix where missing entries are interpolated linearly from the known ones.
    [n_row, n_col] = size(H_ls);
    % interpolate along rows first
    for i = 1:n_row
        curr_row = H_ls(i, :);
        nonzero_inds = find(curr_row);
        % continue if we have a row of zeros
        try
            new_row = interp1(nonzero_inds, curr_row(nonzero_inds), ...
                1:1:n_col, "linear", "extrap");
            H_ls(i, :) = new_row;
        catch
            continue
        end
    end
    % interpolate along columns
    for i = 1:n_col
        curr_col = H_ls(:, i);
        nonzero_inds = find(curr_col);
        % the only case where we have a column of zeros is when the entire
        % matrix is 0
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
