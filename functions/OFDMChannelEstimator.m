% Author: Berkay Guler
% Date: 20.11.2025
% OFDM Channel Estimator Class

classdef OFDMChannelEstimator < handle
    % OFDMChannelEstimator - OFDM channel estimation for 5G NR systems
    %
    %   This class provides comprehensive channel estimation capabilities for
    %   OFDM-based 5G New Radio (NR) systems. It supports least squares (LS)
    %   channel estimation with bilinear interpolation, as well as perfect
    %   channel estimation for benchmarking purposes.
    %
    %   The class implements a complete OFDM transmission chain including:
    %   - Resource grid generation with configurable pilot patterns
    %   - OFDM modulation and demodulation
    %   - TDL/CDL channel modeling with configurable delay spread and Doppler
    %   - Timing synchronization
    %   - AWGN noise addition
    %   - Multiple channel estimation methods
    %
    %   Properties (Constant):
    %       SUBCARRIERS_PER_RB - Number of subcarriers per resource block (12)
    %       QPSK_M             - QPSK modulation order (4)
    %       DEFAULT_NRB        - Default number of resource blocks (10)
    %       DEFAULT_SCS        - Default subcarrier spacing in kHz (15)
    %
    %   Example:
    %       estimator = OFDMChannelEstimator;
    %       [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = ...
    %           estimator.estimate(20, 100, 10, 'TDL-A', 30.72e6, 3, 0, [3 12]);
    %
    %   See also: nrCarrierConfig, nrTDLChannel, bilinear_interp
    
    properties (Constant)
        % SUBCARRIERS_PER_RB - Number of subcarriers per resource block
        %   Standard 5G NR constant: 12 subcarriers per resource block
        SUBCARRIERS_PER_RB = 12;
        
        % QPSK_M - QPSK modulation order
        %   Number of symbols in QPSK constellation: 4
        QPSK_M = 4;
        
        % DEFAULT_NRB - Default number of resource blocks
        %   Default value: 10 resource blocks (120 subcarriers)
        DEFAULT_NRB = 10;
        
        % DEFAULT_SCS - Default subcarrier spacing in kHz
        %   Default value: 15 kHz (standard 5G NR subcarrier spacing)
        DEFAULT_SCS = 15;
    end
    
    properties (Access = private)
        % carrier - 5G NR carrier configuration object
        %   nrCarrierConfig object specifying carrier parameters
        carrier
        
        % resource_grid_size - Resource grid dimensions
        %   [num_subcarriers x num_symbols] vector specifying grid size
        resource_grid_size
        
        % pilot_row_indices - Row indices for pilot symbols
        %   Vector of subcarrier indices where pilots are placed
        pilot_row_indices
        
        % pilot_col_indices - Column indices for pilot symbols
        %   Vector of OFDM symbol indices where pilots are placed
        pilot_col_indices
        
        % n_tx_ants - Number of transmit antennas
        %   Default: 1 (SISO configuration)
        n_tx_ants = 1
        
        % n_rx_ants - Number of receive antennas
        %   Default: 1 (SISO configuration)
        n_rx_ants = 1
        
        % delay_spread_sec - RMS delay spread in seconds
        %   Converted from nanoseconds, used for channel model configuration
        delay_spread_sec
        
        % timing_offset - Estimated timing offset in samples
        %   Used for waveform synchronization before OFDM demodulation
        timing_offset
    end
    
    methods (Access = public)
        function [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = estimate(obj, SNR, ...
                delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices)
            % estimate - Perform complete OFDM channel estimation pipeline
            %
            %   This is the main method that orchestrates the entire channel
            %   estimation process from pilot generation to final channel estimates.
            %
            %   Syntax:
            %       [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = ...
            %           obj.estimate(SNR, delay_spread, max_dopp_shift, ...
            %           delay_profile, sample_rate, N, offset, pilot_col_indices)
            %
            %   Input Arguments:
            %       SNR              - Signal-to-noise ratio in dB (scalar)
            %                          Typical range: -10 to 30 dB
            %       delay_spread     - RMS delay spread in nanoseconds (scalar, > 0)
            %                          Typical range: 10-1000 ns
            %       max_dopp_shift   - Maximum Doppler shift in Hz (scalar, >= 0)
            %                          Typical range: 0-1000 Hz
            %       delay_profile    - Channel delay profile (string/char)
            %                          Valid: 'TDL-A', 'TDL-B', 'TDL-C', 'TDL-D', 'TDL-E',
            %                                 'CDL-A', 'CDL-B', 'CDL-C', 'CDL-D', 'CDL-E'
            %       sample_rate      - Sample rate in Hz (scalar, > 0)
            %                          Typical range: 1-100 MHz
            %       N                - Pilot spacing in frequency domain (integer, > 0)
            %                          Determines spacing between pilot subcarriers
            %       offset           - Frequency offset for pilot placement (integer, >= 0)
            %                          Optional, default: 0
            %       pilot_col_indices - Column indices for pilot symbols (vector of integers)
            %                          Optional, default: [3 12]
            %
            %   Output Arguments:
            %       H_ideal      - Perfect channel estimate (complex matrix)
            %                     Size: [num_subcarriers x num_symbols]
            %                     Ground truth channel frequency response
            %       H_ls         - Least squares estimate at pilot positions (complex matrix)
            %                     Size: [num_subcarriers x num_symbols]
            %                     Non-zero only at pilot locations
            %       H_interp_ls  - Interpolated LS estimate over full grid (complex matrix)
            %                     Size: [num_subcarriers x num_symbols]
            %                     Full channel estimate using bilinear interpolation
            %       tx_grid      - Transmit resource grid (complex matrix)
            %                     Size: [num_subcarriers x num_symbols]
            %                     Contains QPSK-modulated pilot symbols
            %       var_hat      - Estimated noise variance (scalar)
            %                     Estimated from received pilots
            %
            %   Example:
            %       estimator = OFDMChannelEstimator;
            %       [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = ...
            %           estimator.estimate(20, 100, 10, 'TDL-A', 30.72e6, 3, 0);
            %
            %   See also: validateInputs, initializeGrid, performChannelEstimation
            
            % Set defaults for optional parameters
            if nargin < 9
                pilot_col_indices = [];
            end
            if nargin < 8
                offset = [];
            end
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
            
        end
    end
    
    methods (Access = private)
        function [offset, pilot_col_indices] = setDefaults(~, offset, pilot_col_indices, nargin_count)
            % setDefaults - Set default values for optional parameters
            %
            %   This method assigns default values to optional input parameters
            %   if they are not provided or are empty.
            %
            %   Syntax:
            %       [offset, pilot_col_indices] = setDefaults(~, offset, ...
            %           pilot_col_indices, nargin_count)
            %
            %   Input Arguments:
            %       offset            - Frequency offset (may be empty)
            %       pilot_col_indices - Pilot column indices (may be empty)
            %       nargin_count      - Number of input arguments provided
            %
            %   Output Arguments:
            %       offset            - Frequency offset (default: 0 if not provided)
            %       pilot_col_indices - Pilot column indices (default: [3 12] if not provided)
            %
            %   See also: estimate
            if nargin_count < 9 || isempty(pilot_col_indices)
                pilot_col_indices = [3 12];
            end
            if nargin_count < 8 || isempty(offset)
                offset = 0;
            end
        end
        
        function validateInputs(obj, SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate, N, offset, pilot_col_indices)
            % validateInputs - Comprehensive input validation with detailed error messages
            %
            %   Validates all input parameters for the estimate method, checking
            %   data types, ranges, and logical constraints. Throws errors for
            %   invalid inputs and warnings for unusual but valid values.
            %
            %   Syntax:
            %       validateInputs(obj, SNR, delay_spread, max_dopp_shift, ...
            %           delay_profile, sample_rate, N, offset, pilot_col_indices)
            %
            %   Input Arguments:
            %       SNR              - Signal-to-noise ratio in dB
            %       delay_spread     - RMS delay spread in nanoseconds
            %       max_dopp_shift   - Maximum Doppler shift in Hz
            %       delay_profile    - Channel delay profile string
            %       sample_rate      - Sample rate in Hz
            %       N                - Pilot spacing
            %       offset           - Frequency offset
            %       pilot_col_indices - Pilot column indices
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidSNR - If SNR is invalid
            %       OFDMChannelEstimator:InvalidDelaySpread - If delay_spread is invalid
            %       OFDMChannelEstimator:InvalidDopplerShift - If max_dopp_shift is invalid
            %       OFDMChannelEstimator:InvalidDelayProfile - If delay_profile is invalid
            %       OFDMChannelEstimator:InvalidSampleRate - If sample_rate is invalid
            %       OFDMChannelEstimator:InvalidPilotSpacing - If N is invalid
            %       OFDMChannelEstimator:InvalidOffset - If offset is invalid
            %       OFDMChannelEstimator:InvalidPilotColIndices - If pilot_col_indices is invalid
            %
            %   See also: validateBasicInputs, validatePilotParameters
            try
                obj.validateBasicInputs(SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate);
                obj.validatePilotParameters(N, offset, pilot_col_indices);
            catch ME
                fprintf('Error in input validation: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function validateBasicInputs(obj, SNR, delay_spread, max_dopp_shift, delay_profile, sample_rate)
            % validateBasicInputs - Validate basic signal and channel parameters
            %
            %   Validates the fundamental signal and channel parameters including
            %   SNR, delay spread, Doppler shift, delay profile, and sample rate.
            %   Issues warnings for unusual but valid values.
            %
            %   Syntax:
            %       validateBasicInputs(obj, SNR, delay_spread, max_dopp_shift, ...
            %           delay_profile, sample_rate)
            %
            %   Input Arguments:
            %       SNR            - Signal-to-noise ratio in dB (scalar)
            %       delay_spread   - RMS delay spread in nanoseconds (scalar, > 0)
            %                       Converted to seconds and stored in obj.delay_spread_sec
            %       max_dopp_shift - Maximum Doppler shift in Hz (scalar, >= 0)
            %       delay_profile  - Channel delay profile (string/char)
            %                       Valid profiles: TDL-A/B/C/D/E, CDL-A/B/C/D/E
            %       sample_rate    - Sample rate in Hz (scalar, > 0)
            %
            %   Side Effects:
            %       Sets obj.delay_spread_sec to delay_spread converted to seconds
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidSNR - If SNR is not a numeric scalar
            %       OFDMChannelEstimator:InvalidDelaySpread - If delay_spread is invalid
            %       OFDMChannelEstimator:InvalidDopplerShift - If max_dopp_shift is invalid
            %       OFDMChannelEstimator:InvalidDelayProfile - If delay_profile is invalid
            %       OFDMChannelEstimator:InvalidSampleRate - If sample_rate is invalid
            %
            %   See also: validateInputs
            
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
            % validatePilotParameters - Validate pilot-related parameters
            %
            %   Validates parameters related to pilot symbol placement including
            %   pilot spacing, frequency offset, and pilot column indices.
            %
            %   Syntax:
            %       validatePilotParameters(~, N, offset, pilot_col_indices)
            %
            %   Input Arguments:
            %       N                - Pilot spacing in frequency domain (integer, > 0)
            %                         Determines spacing between pilot subcarriers
            %       offset           - Frequency offset for pilot placement (integer, >= 0)
            %                         Starting subcarrier index for pilot placement
            %       pilot_col_indices - Column indices for pilot symbols (vector of integers)
            %                         Must be positive integers within grid bounds
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidPilotSpacing - If N is not a positive integer
            %       OFDMChannelEstimator:InvalidOffset - If offset is not a non-negative integer
            %       OFDMChannelEstimator:InvalidPilotColIndices - If pilot_col_indices is invalid
            %
            %   See also: validateInputs, validateGridConstraints
            
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
            % initializeGrid - Initialize resource grid and pilot positions
            %
            %   Creates the 5G NR carrier configuration and resource grid, then
            %   calculates and validates pilot symbol positions based on the
            %   provided spacing and offset parameters.
            %
            %   Syntax:
            %       initializeGrid(obj, N, offset, pilot_col_indices)
            %
            %   Input Arguments:
            %       N                - Pilot spacing in frequency domain
            %       offset           - Frequency offset for pilot placement
            %       pilot_col_indices - Column indices for pilot symbols
            %
            %   Side Effects:
            %       Sets obj.carrier - nrCarrierConfig object
            %       Sets obj.resource_grid_size - [num_subcarriers x num_symbols]
            %       Sets obj.pilot_row_indices - Row indices for pilot symbols
            %       Sets obj.pilot_col_indices - Column indices for pilot symbols
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidPilotSpacing - If N exceeds grid size
            %       OFDMChannelEstimator:InvalidOffset - If offset is too large
            %       OFDMChannelEstimator:InvalidPilotPosition - If pilot columns exceed grid
            %
            %   See also: validateGridConstraints, checkPilotSufficiency
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
            % validateGridConstraints - Validate pilot parameters against grid constraints
            %
            %   Ensures that pilot placement parameters are compatible with the
            %   resource grid dimensions. Checks pilot spacing, offset, column
            %   indices, and pilot symmetry.
            %
            %   Syntax:
            %       validateGridConstraints(obj, N, offset, pilot_col_indices)
            %
            %   Input Arguments:
            %       N                - Pilot spacing in frequency domain
            %       offset           - Frequency offset for pilot placement
            %       pilot_col_indices - Column indices for pilot symbols
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidPilotSpacing - If N > num_subcarriers
            %       OFDMChannelEstimator:InvalidOffset - If offset >= num_subcarriers
            %       OFDMChannelEstimator:InvalidPilotPosition - If pilot columns exceed grid
            %
            %   Warnings:
            %       OFDMChannelEstimator:AsymmetricPilots - If pilots are not symmetrically placed
            %
            %   See also: initializeGrid
            
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
            % checkPilotSufficiency - Check if we have sufficient pilots for interpolation
            %
            %   Verifies that there are enough pilot symbols in both frequency
            %   and time dimensions to perform reliable bilinear interpolation.
            %   Issues a warning if the number of pilots is insufficient.
            %
            %   Syntax:
            %       checkPilotSufficiency(obj)
            %
            %   Warnings:
            %       OFDMChannelEstimator:InsufficientPilots - If fewer than 2 pilots
            %                                                 in either dimension
            %
            %   See also: initializeGrid, interpolateLSEstimate
            if length(obj.pilot_row_indices) < 2 || length(obj.pilot_col_indices) < 2
                warning('OFDMChannelEstimator:InsufficientPilots', ...
                    'Very few pilot symbols (%d x %d) may result in poor interpolation', ...
                    length(obj.pilot_row_indices), length(obj.pilot_col_indices));
            end
        end
        
        function tx_grid = generatePilotGrid(obj)
            % generatePilotGrid - Generate pilot symbols and populate transmission grid
            %
            %   Creates a resource grid and populates it with QPSK-modulated pilot
            %   symbols at the specified pilot positions. Pilot symbols are
            %   randomly generated and modulated using QPSK.
            %
            %   Syntax:
            %       tx_grid = generatePilotGrid(obj)
            %
            %   Output Arguments:
            %       tx_grid - Transmit resource grid (complex matrix)
            %                 Size: [num_subcarriers x num_symbols]
            %                 Contains QPSK-modulated pilot symbols at pilot positions,
            %                 zeros elsewhere
            %
            %   Side Effects:
            %       Verifies pilot power is approximately unit power
            %
            %   Warnings:
            %       OFDMChannelEstimator:UnexpectedPilotPower - If pilot power deviates
            %                                                   significantly from 1
            %
            %   See also: verifyPilotPower, estimate
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
            % verifyPilotPower - Verify that pilot symbols have expected unit power
            %
            %   Checks that the average power of pilot symbols is approximately
            %   unity, as expected for QPSK modulation. Issues a warning if
            %   significant deviation is detected.
            %
            %   Syntax:
            %       verifyPilotPower(obj, tx_grid)
            %
            %   Input Arguments:
            %       tx_grid - Transmit resource grid containing pilot symbols
            %
            %   Warnings:
            %       OFDMChannelEstimator:UnexpectedPilotPower - If pilot power deviates
            %                                                   from 1 by more than 0.1
            %
            %   See also: generatePilotGrid
            pilot_power = mean(abs(tx_grid(obj.pilot_row_indices, obj.pilot_col_indices)).^2, 'all');
            if abs(pilot_power - 1) > 0.1
                warning('OFDMChannelEstimator:UnexpectedPilotPower', ...
                    'Pilot power %.3f deviates from expected unit power', pilot_power);
            end
        end
        
        function [rx_waveform, path_gains, channel] = simulateChannel(obj, tx_grid, sample_rate, delay_profile, max_dopp_shift)
            % simulateChannel - OFDM modulation and channel simulation
            %
            %   Performs OFDM modulation of the transmit grid, creates a TDL/CDL
            %   channel model, and simulates transmission through the channel to
            %   obtain the received waveform and path gains.
            %
            %   Syntax:
            %       [rx_waveform, path_gains, channel] = simulateChannel(obj, ...
            %           tx_grid, sample_rate, delay_profile, max_dopp_shift)
            %
            %   Input Arguments:
            %       tx_grid        - Transmit resource grid (complex matrix)
            %       sample_rate    - Sample rate in Hz
            %       delay_profile  - Channel delay profile string
            %       max_dopp_shift - Maximum Doppler shift in Hz
            %
            %   Output Arguments:
            %       rx_waveform - Received waveform after channel (complex vector)
            %                     Size: [num_samples x num_rx_ants]
            %       path_gains  - Channel path gains (complex array)
            %                     Used for perfect channel estimation
            %       channel     - Configured nrTDLChannel object
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidWaveform - If tx_waveform contains NaN/Inf
            %       OFDMChannelEstimator:InvalidRxWaveform - If rx_waveform contains NaN/Inf
            %
            %   See also: createChannelModel, transmitThroughChannel, estimate
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
            % createChannelModel - Create and configure TDL channel model
            %
            %   Creates an nrTDLChannel object and configures it with the specified
            %   parameters including sample rate, delay profile, delay spread, and
            %   maximum Doppler shift.
            %
            %   Syntax:
            %       channel = createChannelModel(obj, sample_rate, delay_profile, max_dopp_shift)
            %
            %   Input Arguments:
            %       sample_rate    - Sample rate in Hz
            %       delay_profile  - Channel delay profile string ('TDL-A', 'TDL-B', etc.)
            %       max_dopp_shift - Maximum Doppler shift in Hz
            %
            %   Output Arguments:
            %       channel - Configured nrTDLChannel object
            %                 Properties set: NumReceiveAntennas, NumTransmitAntennas,
            %                 SampleRate, DelayProfile, DelaySpread, MaximumDopplerShift
            %
            %   See also: simulateChannel, nrTDLChannel
            channel = nrTDLChannel;
            channel.NumReceiveAntennas = obj.n_rx_ants;
            channel.NumTransmitAntennas = obj.n_tx_ants;
            channel.SampleRate = sample_rate;
            channel.DelayProfile = delay_profile;
            channel.DelaySpread = obj.delay_spread_sec;
            channel.MaximumDopplerShift = max_dopp_shift;
        end
        
        function [rx_waveform, path_gains] = transmitThroughChannel(obj, tx_waveform, channel)
            % transmitThroughChannel - Transmit waveform through channel with proper padding
            %
            %   Applies the channel model to the transmit waveform, adding appropriate
            %   padding to account for channel delay. Returns the received waveform
            %   and path gains for perfect channel estimation.
            %
            %   Syntax:
            %       [rx_waveform, path_gains] = transmitThroughChannel(obj, ...
            %           tx_waveform, channel)
            %
            %   Input Arguments:
            %       tx_waveform - Transmit waveform (complex vector)
            %                    Size: [num_samples x num_tx_ants]
            %       channel     - Configured nrTDLChannel object
            %
            %   Output Arguments:
            %       rx_waveform - Received waveform after channel (complex vector)
            %                     Size: [num_samples x num_rx_ants]
            %                     Includes channel effects (fading, delay, etc.)
            %       path_gains  - Channel path gains (complex array)
            %                     Used for perfect channel estimation
            %
            %   Warnings:
            %       OFDMChannelEstimator:LargeChannelDelay - If channel delay is
            %                                                comparable to waveform length
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidRxWaveform - If rx_waveform contains NaN/Inf
            %
            %   See also: simulateChannel, createChannelModel
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
            % synchronizeAndDemodulate - Timing synchronization and OFDM demodulation
            %
            %   Performs timing synchronization on the received waveform using
            %   correlation-based timing estimation, then applies the timing offset
            %   and performs OFDM demodulation to obtain the received resource grid.
            %
            %   Syntax:
            %       rx_grid = synchronizeAndDemodulate(obj, rx_waveform, tx_grid)
            %
            %   Input Arguments:
            %       rx_waveform - Received waveform after channel (complex vector)
            %       tx_grid     - Transmit resource grid (for timing estimation)
            %
            %   Output Arguments:
            %       rx_grid - Demodulated received resource grid (complex matrix)
            %                 Size: [num_subcarriers x num_symbols]
            %
            %   Side Effects:
            %       Sets obj.timing_offset to the estimated timing offset in samples
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidOffset - If timing offset exceeds waveform length
            %       OFDMChannelEstimator:InvalidRxGrid - If rx_grid contains NaN/Inf
            %
            %   See also: applySynchronization, validateDemodulation, estimate
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
            % applySynchronization - Apply timing synchronization to received waveform
            %
            %   Applies the estimated timing offset to the received waveform by
            %   either removing samples (positive offset) or adding zeros (negative
            %   offset) to align the waveform for proper OFDM demodulation.
            %
            %   Syntax:
            %       rx_waveform = applySynchronization(obj, rx_waveform)
            %
            %   Input Arguments:
            %       rx_waveform - Received waveform before synchronization (complex vector)
            %
            %   Output Arguments:
            %       rx_waveform - Synchronized received waveform (complex vector)
            %                     Timing offset has been applied
            %
            %   Side Effects:
            %       Uses obj.timing_offset (must be set before calling)
            %
            %   Warnings:
            %       OFDMChannelEstimator:LargeTimingOffset - If |timing_offset| > 1000 samples
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidOffset - If timing offset exceeds waveform length
            %
            %   See also: synchronizeAndDemodulate
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
            % validateDemodulation - Validate demodulation results
            %
            %   Checks that the demodulated received grid is valid (no NaN or Inf
            %   values) and has the expected dimensions matching the transmit grid.
            %
            %   Syntax:
            %       validateDemodulation(obj, rx_grid, tx_grid)
            %
            %   Input Arguments:
            %       rx_grid - Demodulated received resource grid (complex matrix)
            %       tx_grid - Transmit resource grid for size comparison (complex matrix)
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidRxGrid - If rx_grid contains NaN/Inf values
            %
            %   Warnings:
            %       OFDMChannelEstimator:GridSizeMismatch - If rx_grid and tx_grid sizes differ
            %
            %   See also: synchronizeAndDemodulate
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
            % performChannelEstimation - Add noise and perform channel estimation
            %
            %   Adds AWGN noise to the received grid, estimates noise variance,
            %   and computes three types of channel estimates: perfect (ground truth),
            %   least squares at pilot positions, and interpolated LS over the full grid.
            %
            %   Syntax:
            %       [H_ideal, H_ls, H_interp_ls, var_hat] = performChannelEstimation(...
            %           obj, rx_grid, tx_grid, SNR, path_gains, channel)
            %
            %   Input Arguments:
            %       rx_grid     - Demodulated received resource grid (complex matrix)
            %       tx_grid     - Transmit resource grid (complex matrix)
            %       SNR         - Signal-to-noise ratio in dB
            %       path_gains  - Channel path gains from channel simulation (complex array)
            %       channel     - Channel model object (for perfect estimation)
            %
            %   Output Arguments:
            %       H_ideal     - Perfect channel estimate (complex matrix)
            %                    Size: [num_subcarriers x num_symbols]
            %                    Ground truth channel frequency response
            %       H_ls        - Least squares estimate at pilot positions (complex matrix)
            %                    Size: [num_subcarriers x num_symbols]
            %                    Non-zero only at pilot locations
            %       H_interp_ls - Interpolated LS estimate over full grid (complex matrix)
            %                    Size: [num_subcarriers x num_symbols]
            %                    Full channel estimate using bilinear interpolation
            %       var_hat     - Estimated noise variance (scalar)
            %
            %   See also: computePerfectChannelEstimate, computeLSEstimate, interpolateLSEstimate
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
            % validateNoiseVariance - Validate and potentially correct noise variance estimate
            %
            %   Checks that the estimated noise variance is valid (positive and finite).
            %   If invalid, computes a fallback estimate based on the SNR value.
            %
            %   Syntax:
            %       var_hat = validateNoiseVariance(~, var_hat, SNR)
            %
            %   Input Arguments:
            %       var_hat - Estimated noise variance (may be invalid)
            %       SNR     - Signal-to-noise ratio in dB (for fallback calculation)
            %
            %   Output Arguments:
            %       var_hat - Validated noise variance (scalar, > 0, finite)
            %                 If input was invalid, returns 10^(-SNR/10)
            %
            %   Warnings:
            %       OFDMChannelEstimator:InvalidNoiseVariance - If var_hat is invalid
            %
            %   See also: performChannelEstimation
            if var_hat <= 0 || ~isfinite(var_hat)
                warning('OFDMChannelEstimator:InvalidNoiseVariance', ...
                    'Invalid noise variance estimate: %.6f', var_hat);
                var_hat = 10^(-SNR/10);  % Fallback estimate
            end
        end
        
        function H_ideal = computePerfectChannelEstimate(obj, path_gains, channel)
            % computePerfectChannelEstimate - Compute perfect channel estimate using MATLAB functions
            %
            %   Computes the ground truth channel frequency response using the
            %   channel path gains and path filters. This serves as a reference
            %   for evaluating the quality of estimated channel responses.
            %
            %   Syntax:
            %       H_ideal = computePerfectChannelEstimate(obj, path_gains, channel)
            %
            %   Input Arguments:
            %       path_gains - Channel path gains from channel simulation (complex array)
            %                    Obtained from transmitThroughChannel
            %       channel    - Channel model object (nrTDLChannel)
            %                    Used to extract path filters
            %
            %   Output Arguments:
            %       H_ideal - Perfect channel estimate (complex matrix)
            %                 Size: [num_subcarriers x num_symbols]
            %                 Ground truth channel frequency response
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidIdealChannel - If H_ideal contains NaN/Inf
            %
            %   See also: performChannelEstimation, nrPerfectChannelEstimate
            pathFilters = getPathFilters(channel);
            H_ideal = nrPerfectChannelEstimate(obj.carrier, path_gains, pathFilters, obj.timing_offset);
            
            if any(~isfinite(H_ideal), 'all')
                error('OFDMChannelEstimator:InvalidIdealChannel', 'Perfect channel estimate contains NaN or Inf values');
            end
        end
        
        function H_ls = computeLSEstimate(obj, rx_grid, tx_grid)
            % computeLSEstimate - Compute least squares channel estimate at pilot positions
            %
            %   Performs least squares channel estimation at pilot symbol positions
            %   by dividing received pilot symbols by transmitted pilot symbols.
            %   The estimate is zero everywhere except at pilot locations.
            %
            %   Syntax:
            %       H_ls = computeLSEstimate(obj, rx_grid, tx_grid)
            %
            %   Input Arguments:
            %       rx_grid - Demodulated received resource grid (complex matrix)
            %                 Contains received pilot symbols
            %       tx_grid - Transmit resource grid (complex matrix)
            %                 Contains transmitted pilot symbols
            %
            %   Output Arguments:
            %       H_ls - Least squares channel estimate (complex matrix)
            %              Size: [num_subcarriers x num_symbols]
            %              Non-zero only at pilot positions: H_ls = rx_pilots ./ tx_pilots
            %
            %   Side Effects:
            %       Handles very small pilot symbols to avoid numerical issues
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidLSEstimate - If H_ls contains NaN/Inf
            %
            %   See also: handleSmallPilots, interpolateLSEstimate, performChannelEstimation
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
            % handleSmallPilots - Handle very small pilot symbols to avoid numerical issues
            %
            %   Identifies pilot symbols with very small magnitude and replaces them
            %   with a small threshold value to prevent division by zero or near-zero
            %   in least squares channel estimation.
            %
            %   Syntax:
            %       tx_pilots = handleSmallPilots(~, tx_pilots)
            %
            %   Input Arguments:
            %       tx_pilots - Transmitted pilot symbols (complex matrix)
            %
            %   Output Arguments:
            %       tx_pilots - Processed pilot symbols (complex matrix)
            %                   Symbols with |tx_pilots| < 1e-6 are replaced with
            %                   1e-6 * sign(tx_pilots) to maintain phase information
            %
            %   Warnings:
            %       OFDMChannelEstimator:SmallPilotSymbols - If any pilot symbols are very small
            %
            %   See also: computeLSEstimate
            small_pilots = abs(tx_pilots) < 1e-6;
            if any(small_pilots, 'all')
                warning('OFDMChannelEstimator:SmallPilotSymbols', ...
                    'Found %d very small pilot symbols, may cause LS estimation issues', ...
                    sum(small_pilots, 'all'));
                tx_pilots(small_pilots) = 1e-6 * sign(tx_pilots(small_pilots));
            end
        end
        
        function H_interp_ls = interpolateLSEstimate(~, H_ls)
            % interpolateLSEstimate - Interpolate LS estimates to full grid
            %
            %   Interpolates the least squares channel estimates from pilot positions
            %   to all subcarriers and symbols in the resource grid using bilinear
            %   interpolation.
            %
            %   Syntax:
            %       H_interp_ls = interpolateLSEstimate(~, H_ls)
            %
            %   Input Arguments:
            %       H_ls - Least squares channel estimate at pilot positions (complex matrix)
            %              Size: [num_subcarriers x num_symbols]
            %              Non-zero only at pilot locations
            %
            %   Output Arguments:
            %       H_interp_ls - Interpolated LS channel estimate (complex matrix)
            %                    Size: [num_subcarriers x num_symbols]
            %                    Full grid estimate obtained via bilinear interpolation
            %
            %   Throws:
            %       OFDMChannelEstimator:InvalidInterpolation - If H_interp_ls contains NaN/Inf
            %
            %   See also: bilinear_interp, computeLSEstimate, performChannelEstimation
            H_interp_ls = bilinear_interp(H_ls);
            
            if any(~isfinite(H_interp_ls), 'all')
                error('OFDMChannelEstimator:InvalidInterpolation', 'Interpolated channel estimate contains NaN or Inf values');
            end
        end
        
        function assessEstimationQuality(~, H_ideal, H_interp_ls)
            % assessEstimationQuality - Assess and report estimation quality
            %
            %   Computes and reports the mean squared error (MSE) between the perfect
            %   channel estimate and the interpolated LS estimate to assess the
            %   quality of channel estimation.
            %
            %   Syntax:
            %       assessEstimationQuality(~, H_ideal, H_interp_ls)
            %
            %   Input Arguments:
            %       H_ideal     - Perfect channel estimate (complex matrix)
            %                    Ground truth channel frequency response
            %       H_interp_ls - Interpolated LS channel estimate (complex matrix)
            %                    Estimated channel frequency response
            %
            %   Side Effects:
            %       Prints MSE value to console
            %
            %   Warnings:
            %       OFDMChannelEstimator:PoorEstimation - If MSE > 1
            %
            %   See also: performChannelEstimation
            mse_ls = mean(abs(H_ideal - H_interp_ls).^2, 'all');
            fprintf('LS Channel estimation MSE: %.6f\n', mse_ls);
            
            if mse_ls > 1
                warning('OFDMChannelEstimator:PoorEstimation', 'LS channel estimation MSE (%.3f) is quite large', mse_ls);
            end
        end
    end
end