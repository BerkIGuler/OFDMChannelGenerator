% Author: Berkay Guler
% Date: 07.20.2025
% OFDM Channel Estimator Class

classdef OFDMChannelEstimator < handle
    % OFDM Channel Estimation class with comprehensive error checking
    % Provides least squares and perfect channel estimation for 5G NR systems
    
    properties (Constant)
        SUBCARRIERS_PER_RB = 12;  % 5G NR constant
        QPSK_M = 4;               % QPSK modulation order
        DEFAULT_NRB = 10;         % Default number of resource blocks
        DEFAULT_SCS = 15;         % Default subcarrier spacing (kHz)
    end
    
    properties (Access = private)
        carrier
        resource_grid_size
        pilot_row_indices
        pilot_col_indices
        n_tx_ants = 1
        n_rx_ants = 1
        delay_spread_sec
        timing_offset
    end
    
    methods (Access = public)
        function [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = estimate(obj, SNR, ...
                delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices)
            % Main estimation function
            % Returns: H_ideal, H_ls, H_interp_ls, tx_grid, var_hat
            
            % Set defaults and validate inputs
            [offset, pilot_col_indices] = obj.setDefaults(offset, pilot_col_indices, nargin);
            obj.validateInputs(SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices);
            
            % Initialize configuration
            obj.initializeGrid(N, offset, pilot_col_indices);
            
            % Generate pilot symbols and transmit grid
            tx_grid = obj.generatePilotGrid();
            
            % OFDM modulation and channel simulation
            [rx_waveform, path_gains, channel] = obj.simulateChannel(tx_grid, sample_rate, delay_profile, max_dopp_shift);
            
            % Timing synchronization and demodulation
            rx_grid = obj.synchronizeAndDemodulate(rx_waveform, tx_grid);
            
            % Add noise and perform channel estimation
            [H_ideal, H_ls, H_interp_ls, var_hat] = obj.performChannelEstimation(rx_grid, tx_grid, SNR, path_gains, channel);
            
            fprintf('Channel estimation completed successfully!\n');
        end
    end
    
    methods (Access = private)
        function [offset, pilot_col_indices] = setDefaults(~, offset, pilot_col_indices, nargin_count)
            % Set default values for optional parameters
            if nargin_count < 9 || isempty(pilot_col_indices)
                pilot_col_indices = [3 12];
            end
            if nargin_count < 8 || isempty(offset)
                offset = 0;
            end
        end
        
        function validateInputs(obj, SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices)
            % Comprehensive input validation with detailed error messages
            try
                obj.validateBasicInputs(SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate);
                obj.validatePilotParameters(N, offset, pilot_col_indices);
            catch ME
                fprintf('Error in input validation: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function validateBasicInputs(obj, SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate)
            % Validate basic signal and channel parameters
            
            % Validate SNR
            if ~isnumeric(SNR) || ~isscalar(SNR)
                error('OFDMChannelEstimator:InvalidSNR', 'SNR must be a numeric scalar');
            end
            if SNR < -50 || SNR > 50
                warning('OFDMChannelEstimator:UnusualSNR', 'SNR value %.1f dB seems unusual (typical range: -10 to 30 dB)', SNR);
            end
            
            % Validate delay_spread
            if ~isnumeric(delay_spread) || ~isscalar(delay_spread) || delay_spread <= 0
                error('OFDMChannelEstimator:InvalidDelaySpread', 'delay_spread must be a positive numeric scalar');
            end
            obj.delay_spread_sec = delay_spread * 1e-9;  % Convert ns to seconds
            if obj.delay_spread_sec > 1e-3
                warning('OFDMChannelEstimator:LargeDelaySpread', 'Delay spread %.0f ns is very large', delay_spread);
            end
            
            % Validate max_dopp_shift
            if ~isnumeric(max_dopp_shift) || ~isscalar(max_dopp_shift) || max_dopp_shift < 0
                error('OFDMChannelEstimator:InvalidDopplerShift', 'max_dopp_shift must be a non-negative numeric scalar');
            end
            if max_dopp_shift > 1000
                warning('OFDMChannelEstimator:LargeDopplerShift', 'Doppler shift %.1f Hz is very large', max_dopp_shift);
            end
            
            % Validate delay_profile
            valid_profiles = {'TDL-A', 'TDL-B', 'TDL-C', 'TDL-D', 'TDL-E', ...
                             'CDL-A', 'CDL-B', 'CDL-C', 'CDL-D', 'CDL-E'};
            if ~ischar(delay_profile) && ~isstring(delay_profile)
                error('OFDMChannelEstimator:InvalidDelayProfile', 'delay_profile must be a character array or string');
            end
            if ~any(strcmpi(delay_profile, valid_profiles))
                warning('OFDMChannelEstimator:UnknownDelayProfile', ...
                    'Delay profile "%s" may not be supported. Valid profiles: %s', ...
                    delay_profile, strjoin(valid_profiles, ', '));
            end
            
            % Validate sample_rate
            if ~isnumeric(sample_rate) || ~isscalar(sample_rate) || sample_rate <= 0
                error('OFDMChannelEstimator:InvalidSampleRate', 'sample_rate must be a positive numeric scalar');
            end
            if sample_rate < 1e6 || sample_rate > 1e9
                warning('OFDMChannelEstimator:UnusualSampleRate', ...
                    'Sample rate %.2e Hz seems unusual (typical range: 1-100 MHz)', sample_rate);
            end
        end
        
        function validatePilotParameters(~, N, offset, pilot_col_indices)
            % Validate pilot-related parameters
            
            % Validate N (pilot spacing)
            if ~isnumeric(N) || ~isscalar(N) || N <= 0 || N ~= round(N)
                error('OFDMChannelEstimator:InvalidPilotSpacing', 'N must be a positive integer');
            end
            
            % Validate offset
            if ~isnumeric(offset) || ~isscalar(offset) || offset < 0 || offset ~= round(offset)
                error('OFDMChannelEstimator:InvalidOffset', 'offset must be a non-negative integer');
            end
            
            % Validate pilot_col_indices
            if ~isnumeric(pilot_col_indices) || ~isvector(pilot_col_indices) || any(pilot_col_indices <= 0) || any(pilot_col_indices ~= round(pilot_col_indices))
                error('OFDMChannelEstimator:InvalidPilotColIndices', 'pilot_col_indices must be a vector of positive integers');
            end
        end
        
        function initializeGrid(obj, N, offset, pilot_col_indices)
            % Initialize resource grid and pilot positions
            try
                % Create carrier configuration
                obj.carrier = nrCarrierConfig('NSizeGrid', obj.DEFAULT_NRB, 'SubcarrierSpacing', obj.DEFAULT_SCS);
                obj.resource_grid_size = [obj.SUBCARRIERS_PER_RB * obj.DEFAULT_NRB, obj.carrier.SymbolsPerSlot];
                
                % Validate parameters against grid size
                obj.validateGridConstraints(N, offset, pilot_col_indices);
                
                % Set pilot indices
                obj.pilot_row_indices = (offset + 1): N: obj.resource_grid_size(1);
                obj.pilot_col_indices = pilot_col_indices;
                
                % Check pilot sufficiency
                obj.checkPilotSufficiency();
                
                fprintf('Grid size: %dx%d, Pilots: %dx%d\n', ...
                    obj.resource_grid_size(1), obj.resource_grid_size(2), ...
                    length(obj.pilot_row_indices), length(obj.pilot_col_indices));
                
            catch ME
                fprintf('Error in grid configuration: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function validateGridConstraints(obj, N, offset, pilot_col_indices)
            % Validate pilot parameters against grid constraints
            
            % Check pilot spacing
            if N > obj.resource_grid_size(1)
                error('OFDMChannelEstimator:InvalidPilotSpacing', ...
                    'Pilot spacing N=%d exceeds number of subcarriers (%d)', N, obj.resource_grid_size(1));
            end
            
            % Check offset
            if offset >= obj.resource_grid_size(1)
                error('OFDMChannelEstimator:InvalidOffset', ...
                    'Offset=%d must be less than number of subcarriers (%d)', offset, obj.resource_grid_size(1));
            end
            
            % Check pilot column indices
            if any(pilot_col_indices > obj.resource_grid_size(2))
                error('OFDMChannelEstimator:InvalidPilotPosition', 'Pilot column indices exceed grid dimensions');
            end
            
            % Check pilot symmetry
            usable_subcarriers = obj.resource_grid_size(1) - 2*offset - 1;
            if usable_subcarriers <= 0
                error('OFDMChannelEstimator:InvalidOffset', ...
                    'Offset=%d is too large for %d subcarriers', offset, obj.resource_grid_size(1));
            end
            if mod(usable_subcarriers, N) ~= 0
                warning('OFDMChannelEstimator:AsymmetricPilots', ...
                    'Pilots across subcarriers are not symmetrical: (%d - 2*%d - 1) = %d is not divisible by N=%d', ...
                    obj.resource_grid_size(1), offset, usable_subcarriers, N);
            end
        end
        
        function checkPilotSufficiency(obj)
            % Check if we have sufficient pilots for interpolation
            if length(obj.pilot_row_indices) < 2 || length(obj.pilot_col_indices) < 2
                warning('OFDMChannelEstimator:InsufficientPilots', ...
                    'Very few pilot symbols (%d x %d) may result in poor interpolation', ...
                    length(obj.pilot_row_indices), length(obj.pilot_col_indices));
            end
        end
        
        function tx_grid = generatePilotGrid(obj)
            % Generate pilot symbols and populate transmission grid
            try
                tx_grid = nrResourceGrid(obj.carrier, obj.n_tx_ants);
                
                % Generate random pilot data
                pilot_data = randi([0 (obj.QPSK_M-1)], ...
                    length(obj.pilot_row_indices), ...
                    length(obj.pilot_col_indices));
                
                % QPSK modulate and place pilots
                tx_grid(obj.pilot_row_indices, obj.pilot_col_indices) = pskmod(pilot_data, ...
                    obj.QPSK_M, pi/obj.QPSK_M);
                
                % Verify pilot power
                obj.verifyPilotPower(tx_grid);
                
            catch ME
                fprintf('Error in pilot generation: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function verifyPilotPower(obj, tx_grid)
            % Verify that pilot symbols have expected unit power
            pilot_power = mean(abs(tx_grid(obj.pilot_row_indices, obj.pilot_col_indices)).^2, 'all');
            if abs(pilot_power - 1) > 0.1
                warning('OFDMChannelEstimator:UnexpectedPilotPower', ...
                    'Pilot power %.3f deviates from expected unit power', pilot_power);
            end
        end
        
        function [rx_waveform, path_gains, channel] = simulateChannel(obj, tx_grid, sample_rate, delay_profile, max_dopp_shift)
            % OFDM modulation and channel simulation
            try
                % OFDM modulation
                ofdm_info = nrOFDMInfo(obj.carrier);
                ofdm_info.SampleRate = sample_rate;
                tx_waveform = nrOFDMModulate(obj.carrier, tx_grid, 'SampleRate', sample_rate);
                
                % Validate waveform
                if any(~isfinite(tx_waveform))
                    error('OFDMChannelEstimator:InvalidWaveform', 'Transmitted waveform contains NaN or Inf values');
                end
                
                % Create and configure channel
                channel = obj.createChannelModel(sample_rate, delay_profile, max_dopp_shift);
                
                % Transmit through channel
                [rx_waveform, path_gains] = obj.transmitThroughChannel(tx_waveform, channel);
                
            catch ME
                fprintf('Error in OFDM modulation or channel simulation: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function channel = createChannelModel(obj, sample_rate, delay_profile, max_dopp_shift)
            % Create and configure TDL channel model
            channel = nrTDLChannel;
            channel.NumReceiveAntennas = obj.n_rx_ants;
            channel.NumTransmitAntennas = obj.n_tx_ants;
            channel.SampleRate = sample_rate;
            channel.DelayProfile = delay_profile;
            channel.DelaySpread = obj.delay_spread_sec;
            channel.MaximumDopplerShift = max_dopp_shift;
        end
        
        function [rx_waveform, path_gains] = transmitThroughChannel(obj, tx_waveform, channel)
            % Transmit waveform through channel with proper padding
            ch_info = info(channel);
            max_ch_delay = ch_info.MaximumChannelDelay;
            
            if max_ch_delay > length(tx_waveform)
                warning('OFDMChannelEstimator:LargeChannelDelay', ...
                    'Channel delay (%d samples) is comparable to waveform length (%d samples)', ...
                    max_ch_delay, length(tx_waveform));
            end
            
            % Transmit with padding
            [rx_waveform, path_gains] = channel([tx_waveform; zeros(max_ch_delay, obj.n_tx_ants)]);
            
            % Validate received waveform
            if any(~isfinite(rx_waveform))
                error('OFDMChannelEstimator:InvalidRxWaveform', 'Received waveform contains NaN or Inf values');
            end
        end
        
        function rx_grid = synchronizeAndDemodulate(obj, rx_waveform, tx_grid)
            % Timing synchronization and OFDM demodulation
            try
                % Estimate and apply timing offset
                obj.timing_offset = nrTimingEstimate(obj.carrier, rx_waveform, tx_grid);
                rx_waveform = obj.applySynchronization(rx_waveform);
                
                % OFDM demodulation
                rx_grid = nrOFDMDemodulate(obj.carrier, rx_waveform);
                
                % Validate results
                obj.validateDemodulation(rx_grid, tx_grid);
                
            catch ME
                fprintf('Error in synchronization or demodulation: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function rx_waveform = applySynchronization(obj, rx_waveform)
            % Apply timing synchronization to received waveform
            if abs(obj.timing_offset) > 1000  % Reasonable threshold
                warning('OFDMChannelEstimator:LargeTimingOffset', ...
                    'Large timing offset (%d samples) detected', obj.timing_offset);
            end
            
            if obj.timing_offset >= 0
                if obj.timing_offset + 1 > length(rx_waveform)
                    error('OFDMChannelEstimator:InvalidOffset', 'Timing offset exceeds waveform length');
                end
                rx_waveform = rx_waveform(1 + obj.timing_offset: end, :);
            else
                rx_waveform = [zeros(-obj.timing_offset, size(rx_waveform, 2)); rx_waveform];
            end
        end
        
        function validateDemodulation(obj, rx_grid, tx_grid)
            % Validate demodulation results
            if any(~isfinite(rx_grid), 'all')
                error('OFDMChannelEstimator:InvalidRxGrid', 'Demodulated grid contains NaN or Inf values');
            end
            
            if any(size(rx_grid) ~= size(tx_grid))
                warning('OFDMChannelEstimator:GridSizeMismatch', ...
                    'Rx grid size %dx%d differs from Tx grid size %dx%d', ...
                    size(rx_grid), size(tx_grid));
            end
        end
        
        function [H_ideal, H_ls, H_interp_ls, var_hat] = performChannelEstimation(obj, rx_grid, tx_grid, SNR, path_gains, channel)
            % Add noise and perform channel estimation
            try
                % Add AWGN noise
                rx_grid = awgn(rx_grid, SNR, 'measured');
                
                % Estimate noise variance
                [~, var_hat, ~] = nrChannelEstimate(obj.carrier, rx_grid, tx_grid);
                var_hat = obj.validateNoiseVariance(var_hat, SNR);
                
                % Perfect channel estimate
                H_ideal = obj.computePerfectChannelEstimate(path_gains, channel);
                
                % LS channel estimate
                H_ls = obj.computeLSEstimate(rx_grid, tx_grid);
                
                % Interpolated LS estimate
                H_interp_ls = obj.interpolateLSEstimate(H_ls);
                
                % Validate and report estimation quality
                obj.assessEstimationQuality(H_ideal, H_interp_ls);
                
            catch ME
                fprintf('Error in channel estimation: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function var_hat = validateNoiseVariance(~, var_hat, SNR)
            % Validate and potentially correct noise variance estimate
            if var_hat <= 0 || ~isfinite(var_hat)
                warning('OFDMChannelEstimator:InvalidNoiseVariance', ...
                    'Invalid noise variance estimate: %.6f', var_hat);
                var_hat = 10^(-SNR/10);  % Fallback estimate
            end
        end
        
        function H_ideal = computePerfectChannelEstimate(obj, path_gains, channel)
            % Compute perfect channel estimate using MATLAB functions
            pathFilters = getPathFilters(channel);
            H_ideal = nrPerfectChannelEstimate(obj.carrier, path_gains, pathFilters, obj.timing_offset);
            
            if any(~isfinite(H_ideal), 'all')
                error('OFDMChannelEstimator:InvalidIdealChannel', 'Perfect channel estimate contains NaN or Inf values');
            end
        end
        
        function H_ls = computeLSEstimate(obj, rx_grid, tx_grid)
            % Compute least squares channel estimate at pilot positions
            H_ls = zeros(obj.resource_grid_size);
            
            % Extract pilot symbols
            rx_pilots = rx_grid(obj.pilot_row_indices, obj.pilot_col_indices);
            tx_pilots = tx_grid(obj.pilot_row_indices, obj.pilot_col_indices);
            
            % Handle small pilot symbols
            tx_pilots = obj.handleSmallPilots(tx_pilots);
            
            % Perform LS estimation
            H_ls(obj.pilot_row_indices, obj.pilot_col_indices) = rx_pilots ./ tx_pilots;
            
            if any(~isfinite(H_ls), 'all')
                error('OFDMChannelEstimator:InvalidLSEstimate', 'LS channel estimate contains NaN or Inf values');
            end
        end
        
        function tx_pilots = handleSmallPilots(~, tx_pilots)
            % Handle very small pilot symbols to avoid numerical issues
            small_pilots = abs(tx_pilots) < 1e-6;
            if any(small_pilots, 'all')
                warning('OFDMChannelEstimator:SmallPilotSymbols', ...
                    'Found %d very small pilot symbols, may cause LS estimation issues', ...
                    sum(small_pilots, 'all'));
                tx_pilots(small_pilots) = 1e-6 * sign(tx_pilots(small_pilots));
            end
        end
        
        function H_interp_ls = interpolateLSEstimate(~, H_ls)
            % Interpolate LS estimates to full grid
            H_interp_ls = bilinear_interp(H_ls);
            
            if any(~isfinite(H_interp_ls), 'all')
                error('OFDMChannelEstimator:InvalidInterpolation', 'Interpolated channel estimate contains NaN or Inf values');
            end
        end
        
        function assessEstimationQuality(~, H_ideal, H_interp_ls)
            % Assess and report estimation quality
            mse_ls = mean(abs(H_ideal - H_interp_ls).^2, 'all');
            fprintf('LS Channel estimation MSE: %.6f\n', mse_ls);
            
            if mse_ls > 1
                warning('OFDMChannelEstimator:PoorEstimation', 'LS channel estimation MSE (%.3f) is quite large', mse_ls);
            end
        end
    end
end