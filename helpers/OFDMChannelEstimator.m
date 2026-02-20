% Author: Berkay Guler
% Date: 01.10.2026
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
    %       % Create estimator with configuration (offset computed automatically)
    %       estimator = OFDMChannelEstimator(3.84e6, 'TDL-A', 3);
    %       
    %       % Generate channel estimates (only varying parameters)
    %       [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = ...
    %           estimator.estimate(20, 100, 10);
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
        
        % sample_rate - Sample rate in Hz
        %   Configured at construction time
        sample_rate
        
        % delay_profile - Channel delay profile string
        %   Configured at construction time (e.g., 'TDL-A')
        delay_profile
        
        % timing_offset - Estimated timing offset in samples
        %   Used for waveform synchronization before OFDM demodulation
        timing_offset
    end
    
    methods (Access = public)
        function obj = OFDMChannelEstimator(sample_rate, delay_profile, N, pilot_col_indices)
            % OFDMChannelEstimator - Constructor for OFDM channel estimator
            %
            %   Creates and configures an OFDM channel estimator instance.
            %   All validation is performed during construction. The offset
            %   for symmetric pilot placement is computed automatically.
            %
            %   Syntax:
            %       estimator = OFDMChannelEstimator(sample_rate, delay_profile, N)
            %       estimator = OFDMChannelEstimator(sample_rate, delay_profile, N, pilot_col_indices)
            %
            %   Input Arguments:
            %       sample_rate      - Sample rate in Hz (scalar, > 0)
            %                          Typical range: 1-100 MHz
            %       delay_profile    - Channel delay profile (string/char)
            %                          Valid: 'TDL-A', 'TDL-B', 'TDL-C', 'TDL-D', 'TDL-E',
            %                                 'CDL-A', 'CDL-B', 'CDL-C', 'CDL-D', 'CDL-E'
            %       N                - Pilot spacing in frequency domain (integer, > 0)
            %                          Determines spacing between pilot subcarriers
            %       pilot_col_indices - Column indices for pilot symbols (vector of integers)
            %                          Optional, default: [3 12]
            %
            %   Output Arguments:
            %       obj - Configured OFDMChannelEstimator instance
            %
            %   Note:
            %       The offset for pilot placement is automatically computed to ensure
            %       symmetric pilots across subcarriers. If perfect symmetry is not
            %       achievable for the given N, a warning is issued and offset=0 is used.
            %
            %   Example:
            %       estimator = OFDMChannelEstimator(3.84e6, 'TDL-A', 3);
            %       estimator = OFDMChannelEstimator(3.84e6, 'TDL-A', 3, [3 12]);
            
            % Set defaults for optional parameters
            if nargin < 4 || isempty(pilot_col_indices)
                pilot_col_indices = [3 12];
            end
            
            % Validate and store configuration parameters
            obj.validateAndStoreConfig(sample_rate, delay_profile, N, pilot_col_indices);
            
            % Initialize the resource grid (offset computed automatically)
            obj.initializeGrid(N, pilot_col_indices);
            
            fprintf('OFDMChannelEstimator initialized successfully.\n');
            fprintf('Grid size: %dx%d, Pilots: %dx%d, Offset: %d\n', ...
                obj.resource_grid_size(1), obj.resource_grid_size(2), ...
                length(obj.pilot_row_indices), length(obj.pilot_col_indices), ...
                obj.pilot_row_indices(1) - 1);
        end
        
        function [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = estimate(obj, SNR, delay_spread, max_dopp_shift)
            % estimate - Perform OFDM channel estimation
            %
            %   Generates channel estimates for the given channel conditions.
            %   This method only takes parameters that vary between calls.
            %
            %   Syntax:
            %       [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = ...
            %           obj.estimate(SNR, delay_spread, max_dopp_shift)
            %
            %   Input Arguments:
            %       SNR              - Signal-to-noise ratio in dB (scalar)
            %                          Typical range: -10 to 30 dB
            %       delay_spread     - RMS delay spread in nanoseconds (scalar, > 0)
            %                          Typical range: 10-1000 ns
            %       max_dopp_shift   - Maximum Doppler shift in Hz (scalar, >= 0)
            %                          Typical range: 0-1000 Hz
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
            %       estimator = OFDMChannelEstimator(3.84e6, 'TDL-A', 3);
            %       [H_ideal, H_ls, H_interp_ls, tx_grid, var_hat] = ...
            %           estimator.estimate(20, 100, 50);
            
            % Convert delay spread from ns to seconds
            delay_spread_sec = delay_spread * 1e-9;
            
            % Generate pilot symbols and transmit grid
            tx_grid = obj.generatePilotGrid();
            
            % OFDM modulation and channel simulation
            [rx_waveform, path_gains, channel] = obj.simulateChannel(tx_grid, delay_spread_sec, max_dopp_shift);
            
            % Timing synchronization and demodulation
            rx_grid = obj.synchronizeAndDemodulate(rx_waveform, tx_grid);
            
            % Add noise and perform channel estimation
            [H_ideal, H_ls, H_interp_ls, var_hat] = obj.performChannelEstimation(rx_grid, tx_grid, SNR, path_gains, channel);
        end
    end
    
    methods (Access = private)
        function validateAndStoreConfig(obj, sample_rate, delay_profile, N, pilot_col_indices)
            % validateAndStoreConfig - Validate and store configuration parameters
            %
            %   Validates all configuration parameters and stores them in the object.
            %   Called once during construction.
            
            % Validate sample_rate
            if ~isnumeric(sample_rate) || ~isscalar(sample_rate) || sample_rate <= 0
                error('OFDMChannelEstimator:InvalidSampleRate', 'sample_rate must be a positive numeric scalar');
            end
            if sample_rate < 1e6 || sample_rate > 1e9
                warning('OFDMChannelEstimator:UnusualSampleRate', ...
                    'Sample rate %.2e Hz seems unusual (typical range: 1-100 MHz)', sample_rate);
            end
            obj.sample_rate = sample_rate;
            
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
            obj.delay_profile = delay_profile;
            
            % Validate N (pilot spacing)
            if ~isnumeric(N) || ~isscalar(N) || N <= 0 || N ~= round(N)
                error('OFDMChannelEstimator:InvalidPilotSpacing', 'N must be a positive integer');
            end
            
            % Validate pilot_col_indices
            if ~isnumeric(pilot_col_indices) || ~isvector(pilot_col_indices) || any(pilot_col_indices <= 0) || any(pilot_col_indices ~= round(pilot_col_indices))
                error('OFDMChannelEstimator:InvalidPilotColIndices', 'pilot_col_indices must be a vector of positive integers');
            end
        end
        
        function initializeGrid(obj, N, pilot_col_indices)
            % initializeGrid - Initialize resource grid and pilot positions
            %
            %   Creates the 5G NR carrier configuration and resource grid, then
            %   calculates and validates pilot symbol positions. The offset is
            %   computed automatically for symmetric pilot placement.
            
            % Create carrier configuration
            obj.carrier = nrCarrierConfig('NSizeGrid', obj.DEFAULT_NRB, 'SubcarrierSpacing', obj.DEFAULT_SCS);
            obj.resource_grid_size = [obj.SUBCARRIERS_PER_RB * obj.DEFAULT_NRB, obj.carrier.SymbolsPerSlot];
            
            % Validate parameters against grid size
            obj.validateGridConstraints(N, pilot_col_indices);
            
            % Compute offset for symmetric pilot placement
            offset = OFDMChannelEstimator.computeSymmetricOffset(N, obj.resource_grid_size(1));
            if offset < 0
                % Perfect symmetry not achievable, use offset = 0
                offset = 0;
            end
            
            % Set pilot indices
            obj.pilot_row_indices = (offset + 1): N: obj.resource_grid_size(1);
            obj.pilot_col_indices = pilot_col_indices;
            
            % Check pilot sufficiency
            obj.checkPilotSufficiency();
        end
        
        function validateGridConstraints(obj, N, pilot_col_indices)
            % validateGridConstraints - Validate pilot parameters against grid constraints
            
            % Check pilot spacing
            if N > obj.resource_grid_size(1)
                error('OFDMChannelEstimator:InvalidPilotSpacing', ...
                    'Pilot spacing N=%d exceeds number of subcarriers (%d)', N, obj.resource_grid_size(1));
            end
            
            % Check pilot column indices
            if any(pilot_col_indices > obj.resource_grid_size(2))
                error('OFDMChannelEstimator:InvalidPilotPosition', 'Pilot column indices exceed grid dimensions');
            end
        end
        
        function checkPilotSufficiency(obj)
            % checkPilotSufficiency - Check if we have sufficient pilots for interpolation
            
            if length(obj.pilot_row_indices) < 2 || length(obj.pilot_col_indices) < 2
                warning('OFDMChannelEstimator:InsufficientPilots', ...
                    'Very few pilot symbols (%d x %d) may result in poor interpolation', ...
                    length(obj.pilot_row_indices), length(obj.pilot_col_indices));
            end
        end
        
        function tx_grid = generatePilotGrid(obj)
            % generatePilotGrid - Generate pilot symbols and populate transmission grid
            
            tx_grid = nrResourceGrid(obj.carrier, obj.n_tx_ants);
            
            % Generate random pilot data
            pilot_data = randi([0 (obj.QPSK_M-1)], ...
                length(obj.pilot_row_indices), ...
                length(obj.pilot_col_indices));
            
            % QPSK modulate and place pilots
            tx_grid(obj.pilot_row_indices, obj.pilot_col_indices) = pskmod(pilot_data, ...
                obj.QPSK_M, pi/obj.QPSK_M);
        end
        
        function [rx_waveform, path_gains, channel] = simulateChannel(obj, tx_grid, delay_spread_sec, max_dopp_shift)
            % simulateChannel - OFDM modulation and channel simulation
            
            % OFDM modulation
            tx_waveform = nrOFDMModulate(obj.carrier, tx_grid, 'SampleRate', obj.sample_rate);
            
            % Create and configure channel
            channel = obj.createChannelModel(delay_spread_sec, max_dopp_shift);
            
            % Transmit through channel
            [rx_waveform, path_gains] = obj.transmitThroughChannel(tx_waveform, channel);
        end
        
        function channel = createChannelModel(obj, delay_spread_sec, max_dopp_shift)
            % createChannelModel - Create and configure TDL channel model
            
            channel = nrTDLChannel;
            channel.NumReceiveAntennas = obj.n_rx_ants;
            channel.NumTransmitAntennas = obj.n_tx_ants;
            channel.SampleRate = obj.sample_rate;
            channel.DelayProfile = obj.delay_profile;
            channel.DelaySpread = delay_spread_sec;
            channel.MaximumDopplerShift = max_dopp_shift;
        end
        
        function [rx_waveform, path_gains] = transmitThroughChannel(obj, tx_waveform, channel)
            % transmitThroughChannel - Transmit waveform through channel with proper padding
            
            ch_info = info(channel);
            max_ch_delay = ch_info.MaximumChannelDelay;
            
            % Transmit with padding
            [rx_waveform, path_gains] = channel([tx_waveform; zeros(max_ch_delay, obj.n_tx_ants)]);
        end
        
        function rx_grid = synchronizeAndDemodulate(obj, rx_waveform, tx_grid)
            % synchronizeAndDemodulate - Timing synchronization and OFDM demodulation
            
            % Estimate and apply timing offset
            obj.timing_offset = nrTimingEstimate(obj.carrier, rx_waveform, tx_grid);
            rx_waveform = obj.applySynchronization(rx_waveform);
            
            % OFDM demodulation
            rx_grid = nrOFDMDemodulate(obj.carrier, rx_waveform);
        end
        
        function rx_waveform = applySynchronization(obj, rx_waveform)
            % applySynchronization - Apply timing synchronization to received waveform
            
            if obj.timing_offset >= 0
                rx_waveform = rx_waveform(1 + obj.timing_offset: end, :);
            else
                rx_waveform = [zeros(-obj.timing_offset, size(rx_waveform, 2)); rx_waveform];
            end
        end
        
        function [H_ideal, H_ls, H_interp_ls, var_hat] = performChannelEstimation(obj, rx_grid, tx_grid, SNR, path_gains, channel)
            % performChannelEstimation - Add noise and perform channel estimation
            
            % Add AWGN noise
            rx_grid = awgn(rx_grid, SNR, 'measured');
            
            % Estimate noise variance
            [~, var_hat, ~] = nrChannelEstimate(obj.carrier, rx_grid, tx_grid);
            if var_hat <= 0 || ~isfinite(var_hat)
                var_hat = 10^(-SNR/10);  % Fallback estimate
            end
            
            % Perfect channel estimate (use same sample rate as channel/OFDM so path
            % gains map correctly to OFDM symbols; ensure nonnegative timing offset)
            pathFilters = getPathFilters(channel);
            toffset = max(0, obj.timing_offset);
            H_ideal = nrPerfectChannelEstimate(obj.carrier, path_gains, pathFilters, toffset, ...
                'SampleRate', obj.sample_rate);
            
            % LS channel estimate
            H_ls = obj.computeLSEstimate(rx_grid, tx_grid);
            
            % Interpolated LS estimate
            H_interp_ls = bilinear_interp(H_ls);
        end
        
        function H_ls = computeLSEstimate(obj, rx_grid, tx_grid)
            % computeLSEstimate - Compute least squares channel estimate at pilot positions
            
            H_ls = zeros(obj.resource_grid_size);
            
            % Extract pilot symbols
            rx_pilots = rx_grid(obj.pilot_row_indices, obj.pilot_col_indices);
            tx_pilots = tx_grid(obj.pilot_row_indices, obj.pilot_col_indices);
            
            % Perform LS estimation
            H_ls(obj.pilot_row_indices, obj.pilot_col_indices) = rx_pilots ./ tx_pilots;
        end
    end
    
    methods (Static)
        function offset = computeSymmetricOffset(N, num_subcarriers)
            % computeSymmetricOffset - Calculate offset for symmetric pilot placement
            %
            %   Computes the offset needed so that pilots are placed symmetrically
            %   across subcarriers. The first pilot will be at the same distance
            %   from the start as the last pilot is from the end.
            %
            %   Syntax:
            %       offset = OFDMChannelEstimator.computeSymmetricOffset(N)
            %       offset = OFDMChannelEstimator.computeSymmetricOffset(N, num_subcarriers)
            %
            %   Input Arguments:
            %       N               - Pilot spacing in frequency domain (integer, > 0)
            %       num_subcarriers - Total number of subcarriers (optional, default: 120)
            %
            %   Output Arguments:
            %       offset - Optimal offset for symmetric pilot placement
            %                Returns -1 if perfect symmetry is not achievable
            %
            %   Example:
            %       % For N=3 with 120 subcarriers
            %       offset = OFDMChannelEstimator.computeSymmetricOffset(3);
            %       % Returns 1
            %
            %   Mathematical Background:
            %       Pilot positions are at: (offset+1), (offset+1+N), (offset+1+2N), ...
            %       For symmetry, we need: (num_subcarriers - 1 - 2*offset) mod N == 0
            %       Rearranging: 2*offset mod N == (num_subcarriers - 1) mod N
            
            if nargin < 2
                num_subcarriers = 120;  % Default: 10 RBs * 12 subcarriers
            end
            
            remainder = mod(num_subcarriers - 1, N);
            
            % Find smallest non-negative offset such that 2*offset mod N == remainder
            for offset = 0:N-1
                if mod(2 * offset, N) == remainder
                    return;
                end
            end
            
            % No exact solution exists (happens when N is even and remainder is odd)
            % Return -1 to indicate perfect symmetry is not achievable
            offset = -1;
            warning('OFDMChannelEstimator:NoSymmetricOffset', ...
                'Perfect symmetric pilot placement is not achievable for N=%d with %d subcarriers.', ...
                N, num_subcarriers);
        end
    end
end
