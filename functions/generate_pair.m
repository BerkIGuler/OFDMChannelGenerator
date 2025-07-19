% Author: Berkay Guler
% Date: 25.04.2024
% Revised: 08.06.2024

% generates LS, and perfect OFDM channel estimates

function [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = generate_pair(SNR, ...
    delay_spread, max_dopp_shift, delay_profile, sample_rate, N)
    % SNR: Signal to noise ratio in dB
    % delay_spread: delay spread of the generated channel in ns
    % max_dopp_shift: maximum Doppler shift in the generated channel
    % delay_profile: Delay profile name from 3GPP. 
                                % i.e. NLOS, LOS, etc. what kind of paths we have
    % sample_rate: sample rate of the simulated input signal
    % N: insert pilots once every N rows
    
    % H_ideal: perfect channel estimate, calculated by MATLAB
    % H_ls: Least Squares channel estimations at pilot positions
    % H_interp_ls: Interpolated LS Channel Estimate
    % tx_grid: transmitted resource grid, could be used for noise variance
        % estimation
    % var_hat: estimated noise variance


    % constant subcarriers per resource block
    SUBCARRIERS_PER_RB = 12;

    % QPSK
    M = 4;
    
    % Create a resource grid
    nrb = 10;  % num resource blocks
    scs = 15;  % sub-carrier spacing in kHz
    carrier = nrCarrierConfig( 'NSizeGrid', nrb, 'SubcarrierSpacing', scs);
    n_tx_ants = 1;  % num tx antennas
    n_rx_ants = 1;  % num rx antennas
    resource_grid_size = [SUBCARRIERS_PER_RB*nrb carrier.SymbolsPerSlot]; 
    pilot_row_indices = 1: N: resource_grid_size(1);  % subcarriers pilot indices
    pilot_col_indices = [3 12];  % ofdm pilot indices
                                                       % can also arbitrarily choose
                                                       % a pattern for pilots
    
    tx_grid = nrResourceGrid(carrier, n_tx_ants);  % grid empty initially
    % generate random tx data to be sent as pilots
    pilot_data = randi([0 (M-1)], ...
        length(pilot_row_indices), ...
        length(pilot_col_indices));
    
    % modulate pilot signals and populate only the pilot positions
    % other cells are 0
    tx_grid(pilot_row_indices, pilot_col_indices) = pskmod(pilot_data, ...
        M, pi/M);  % QPSK modulate
    
    % OFDM Modulate the resource grid
    % FFT size is auto selected
    % CP length is 18 or 20 based on the OFDM symbol index
    ofdm_info = nrOFDMInfo(carrier);
    ofdm_info.SampleRate = sample_rate;
    tx_waveform = nrOFDMModulate(carrier, tx_grid, 'SampleRate', sample_rate);
    
    % Create a TDL channel model
    channel = nrTDLChannel;
    channel.NumReceiveAntennas = n_rx_ants;
    channel.NumTransmitAntennas = n_tx_ants;
    channel.SampleRate = ofdm_info.SampleRate;
    channel.DelayProfile = delay_profile;
    channel.DelaySpread = delay_spread;  % in seconds
    channel.MaximumDopplerShift = max_dopp_shift;  % in Hz
    
    % Get the maximum channel delay.
    ch_info = info(channel);
    max_ch_delay = ch_info.MaximumChannelDelay;
    
    % To flush delayed samples from the channel,
    % append zeros at the end of the
    % transmitted waveform corresponding to the maximum number of
    % delayed samples and the number of transmit antennas. 
    % Transmit the padded waveform through the TDL-C channel model.
    [rx_waveform, path_gains] = channel([tx_waveform; ...
        zeros(max_ch_delay,n_tx_ants)]);
    
    % Estimate timing offset for the transmission
    % The OFDM modulation of the reference symbols
    % uses an initial slot number of 0
    offset = nrTimingEstimate(carrier, rx_waveform, tx_grid);
    
    % Synchronize the received waveform
    % according to the estimated timing offset.
    rx_waveform = rx_waveform(1 + offset: end, :);
    
    % Create a received resource grid containing 
    % the demodulated and synchronized received waveform
    rx_grid = nrOFDMDemodulate(carrier, rx_waveform);
    
    % add awgn noise
    rx_grid = awgn(rx_grid, SNR, 'measured');
    
    % estimate noise variance
    [~, var_hat, ~] = nrChannelEstimate(carrier, rx_grid, tx_grid);

    % perfect channel estimate.
    pathFilters = getPathFilters(channel);
    H_ideal = nrPerfectChannelEstimate(carrier, path_gains, ...
        pathFilters, offset);
    
    % LS estimate
    H_ls = zeros(resource_grid_size);
    H_ls(pilot_row_indices, pilot_col_indices) = rx_grid( ...
        pilot_row_indices, pilot_col_indices) ./ ...
        tx_grid(pilot_row_indices, pilot_col_indices);
    H_interp_ls = bilinear_interp(H_ls);
end
