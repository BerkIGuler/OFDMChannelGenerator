% Author: Berkay Guler
% Date: 07.20.2025
% API wrapper function for OFDM Channel Estimation

function [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = generate_pair(SNR, ...
    delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices)
    % generates least squares at positions and perfect OFDM channel estimates
    % for each channel element
    %
    % INPUTS:
    % SNR: Signal to noise ratio in dB
    % delay_spread: delay spread of the generated channel in ns
    % max_dopp_shift: maximum Doppler shift in the generated channel in Hz
    % delay_profile: Delay profile name from 3GPP (e.g., 'TDL-A', 'CDL-B')
    % sample_rate: sample rate of the simulated OFDM signal
    % N: insert pilots once every N rows (subcarrier spacing)
    % offset: number of subcarriers to skip before starting pilots (optional, default: 0)
    % pilot_col_indices: OFDM symbol indices for pilots (optional, default: [3 12])
    %
    % OUTPUTS:
    % H_ideal: perfect channel estimate (by MATLAB built-in function)
    % H_ls: Least Squares channel estimations with zeros at non-pilot positions
    % H_interp_ls: bilinearly interpolated LS channel estimate
    % tx_grid: transmitted resource grid with pilot symbols and zeros elsewhere
    % var_hat: estimated noise variance (by MATLAB built-in function)
    %
    % USAGE EXAMPLES:
    % % Basic usage with defaults
    % [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = generate_pair(10, 100, 50, 'TDL-A', 15.36e6, 4);
    %
    % % With custom offset
    % [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = generate_pair(10, 100, 50, 'TDL-A', 15.36e6, 4, 2);
    %
    % % With custom offset and pilot columns
    % [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = generate_pair(10, 100, 50, 'TDL-A', 15.36e6, 4, 2, [1 5 9]);
    
    % Check minimum required arguments
    if nargin < 6
        error('generate_pair:InvalidInput', ...
            'Function requires at least 6 input arguments: SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate, N');
    end
    
    % Create estimator instance and run estimation
    estimator = OFDMChannelEstimator();
    
    % Handle optional arguments for the class method
    if nargin >= 8
        [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = estimator.estimate(SNR, ...
            delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices);
    elseif nargin == 7
        [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = estimator.estimate(SNR, ...
            delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, []);
    else
        [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = estimator.estimate(SNR, ...
            delay_spread, max_dopp_shift, delay_profile, sample_rate, N, [], []);
    end
end