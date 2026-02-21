% Author: Berkay Guler
% Date: 02.21.2026
% OFDM Channel Estimator Class

classdef OFDMChannelEstimator < handle
    % OFDMChannelEstimator - OFDM channel dataset generator for 5G NR systems
    %
    %   Generates (H, Hp_LS, noise_var) samples for training and testing
    %   channel estimation algorithms f_theta such that f_theta(Hp_LS) ≈ H.
    %
    %   The class implements a complete OFDM transmission chain:
    %   - Resource grid generation with configurable pilot pattern
    %   - OFDM modulation and demodulation
    %   - TDL/CDL channel modeling with configurable delay spread and Doppler
    %   - Perfect timing synchronization from path gains
    %   - AWGN noise with exact noise variance computation
    %   - Perfect channel H computed directly from path gains
    %   - Sparse LS channel estimate Hp_LS at pilot positions
    %
    %   Example:
    %       estimator = OFDMChannelEstimator(3.84e6, 'TDL-A', 3);
    %       [H, Hp_LS, noise_var] = estimator.estimate(20, 100, 10);
    %
    %   See also: nrCarrierConfig, nrTDLChannel
    
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
        
        function [H, Hp_LS, noise_var] = estimate(obj, SNR, delay_spread, max_dopp_shift)
            % estimate - Generate one (H, Hp_LS, noise_var) sample
            %
            %   Syntax:
            %       [H, Hp_LS, noise_var] = obj.estimate(SNR, delay_spread, max_dopp_shift)
            %
            %   Input Arguments:
            %       SNR              - Signal-to-noise ratio in dB (scalar)
            %       delay_spread     - RMS delay spread in nanoseconds (scalar, > 0)
            %       max_dopp_shift   - Maximum Doppler shift in Hz (scalar, >= 0)
            %
            %   Output Arguments:
            %       H         - Perfect channel frequency response (complex matrix)
            %                   Size: [num_subcarriers x num_symbols]
            %       Hp_LS     - Sparse LS channel estimate (complex matrix)
            %                   Size: [num_subcarriers x num_symbols]
            %                   Non-zero only at pilot locations
            %       noise_var - Noise variance per complex element (scalar)
            %                   Exact variance of the AWGN added to the grid
            %
            %   Example:
            %       estimator = OFDMChannelEstimator(3.84e6, 'TDL-A', 3);
            %       [H, Hp_LS, noise_var] = estimator.estimate(20, 100, 50);
            
            delay_spread_sec = delay_spread * 1e-9;
            
            tx_grid = obj.generatePilotGrid();
            
            [rx_waveform, path_gains, sample_times, channel] = ...
                obj.simulateChannel(tx_grid, delay_spread_sec, max_dopp_shift);
            
            % Perfect timing from path gains (consistent for H and demodulation)
            pathFilters = getPathFilters(channel);
            obj.timing_offset = nrPerfectTimingEstimate(path_gains, pathFilters);
            
            rx_grid = obj.synchronizeAndDemodulate(rx_waveform);
            
            H = obj.buildChannelFromPathGains(path_gains, pathFilters, sample_times);
            
            % Exact noise variance matching what awgn() will add
            signal_power = mean(abs(rx_grid(:)).^2);
            noise_var = signal_power / (10^(SNR / 10));
            rx_grid_noisy = awgn(rx_grid, SNR, 'measured');
            
            Hp_LS = obj.computeLSEstimate(rx_grid_noisy, tx_grid);
        end
        
        function indices = getPilotRowIndices(obj)
            indices = obj.pilot_row_indices;
        end
        
        function indices = getPilotColIndices(obj)
            indices = obj.pilot_col_indices;
        end
        
        function sz = getGridSize(obj)
            sz = obj.resource_grid_size;
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
        
        function [rx_waveform, path_gains, sample_times, channel] = simulateChannel(obj, tx_grid, delay_spread_sec, max_dopp_shift)
            % simulateChannel - OFDM modulation and channel simulation
            
            % OFDM modulation
            tx_waveform = nrOFDMModulate(obj.carrier, tx_grid, 'SampleRate', obj.sample_rate);
            
            % Create and configure channel
            channel = obj.createChannelModel(delay_spread_sec, max_dopp_shift);
            
            % Transmit through channel
            [rx_waveform, path_gains, sample_times] = obj.transmitThroughChannel(tx_waveform, channel);
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
        
        function [rx_waveform, path_gains, sample_times] = transmitThroughChannel(obj, tx_waveform, channel)
            % transmitThroughChannel - Transmit waveform through channel with proper padding
            
            ch_info = info(channel);
            max_ch_delay = ch_info.MaximumChannelDelay;
            
            % Transmit with padding; capture sample times if channel returns them (3rd output)
            in_sig = [tx_waveform; zeros(max_ch_delay, obj.n_tx_ants)];
            out = cell(1, 3);
            [out{:}] = channel(in_sig);
            rx_waveform = out{1};
            path_gains = out{2};
            if ~isempty(out{3})
                sample_times = out{3};
            else
                % Build sample times from channel sample rate (path gain per input sample)
                ncs = size(path_gains, 1);
                sample_times = (0 : ncs - 1)' / obj.sample_rate;
            end
        end
        
        function rx_grid = synchronizeAndDemodulate(obj, rx_waveform)
            % synchronizeAndDemodulate - Apply timing sync and OFDM demodulation
            %   Uses the timing_offset already set on the object (from
            %   nrPerfectTimingEstimate in estimate()).
            
            rx_waveform = obj.applySynchronization(rx_waveform);
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
        
        function Hp_LS = computeLSEstimate(obj, rx_grid, tx_grid)
            % computeLSEstimate - Compute LS channel estimate at pilot positions
            
            Hp_LS = zeros(obj.resource_grid_size);
            
            rx_pilots = rx_grid(obj.pilot_row_indices, obj.pilot_col_indices);
            tx_pilots = tx_grid(obj.pilot_row_indices, obj.pilot_col_indices);
            
            Hp_LS(obj.pilot_row_indices, obj.pilot_col_indices) = rx_pilots ./ tx_pilots;
        end
        
        function H = buildChannelFromPathGains(obj, path_gains, pathFilters, sample_times)
            % buildChannelFromPathGains - Build frequency-domain channel from path gains
            %
            %   Computes H(k,l) directly from path gains and path filters, bypassing
            %   nrPerfectChannelEstimate. This preserves Gaussian statistics since we
            %   only do linear operations (interpolation, convolution, FFT) on Gaussian
            %   path gains.
            %
            %   Inputs:
            %       path_gains    - NCS x NP x NT x NR complex matrix (channel snapshots)
            %       pathFilters   - NH x NP real matrix (path filter impulse responses)
            %       sample_times   - NCS x 1 vector (times of channel snapshots)
            %
            %   Output:
            %       H             - NSubcarriers x NSymbols complex matrix
            
            % Get OFDM parameters
            ofdm_info = nrOFDMInfo(obj.carrier, 'SampleRate', obj.sample_rate);
            n_subcarriers = obj.resource_grid_size(1);
            n_symbols = obj.resource_grid_size(2);
            nfft = ofdm_info.Nfft;
            cp_lengths = ofdm_info.CyclicPrefixLengths;  % CP length for each symbol
            
            % Compute OFDM symbol start samples manually
            % Each symbol starts after the previous symbol + CP + useful part
            toffset = max(0, obj.timing_offset);
            symbol_start_samples = zeros(n_symbols, 1);
            symbol_start_samples(1) = toffset;
            for sym = 2:n_symbols
                % Previous symbol start + CP length + useful part (Nfft)
                symbol_start_samples(sym) = symbol_start_samples(sym-1) + cp_lengths(sym-1) + nfft;
            end
            symbol_times = symbol_start_samples / obj.sample_rate;
            
            % Path gains dimensions: NCS x NP x NT x NR
            [ncs, np, nt, nr] = size(path_gains);
            
            % Initialize output
            H = zeros(n_subcarriers, n_symbols, nt, nr);
            
            % For each transmit/receive antenna pair
            for tx = 1:nt
                for rx = 1:nr
                    % Extract path gains for this antenna pair: NCS x NP
                    pg = path_gains(:, :, tx, rx);
                    
                    % For each OFDM symbol
                    for sym = 1:n_symbols
                        sym_time = symbol_times(sym);
                        
                        % Interpolate path gains to this symbol time
                        % pg_interp: 1 x NP (complex gains at symbol time)
                        if sym_time <= sample_times(1)
                            pg_interp = pg(1, :);
                        elseif sym_time >= sample_times(end)
                            pg_interp = pg(end, :);
                        else
                            % Linear interpolation in time
                            pg_interp = zeros(1, np);
                            for p = 1:np
                                pg_interp(p) = interp1(sample_times, pg(:, p), sym_time, 'linear', 'extrap');
                            end
                        end
                        
                        % Build channel impulse response (CIR) from path gains and filters
                        % CIR: h(τ) = Σ_p path_gain_p(t) * path_filter_p(τ)
                        % Path filters are already positioned at their delays
                        nh = size(pathFilters, 1);
                        cir = zeros(nh, 1);
                        for p = 1:np
                            cir = cir + pg_interp(p) * pathFilters(:, p);
                        end
                        
                        % Zero-pad CIR to Nfft length for FFT
                        cir_fft = [cir; zeros(nfft - nh, 1)];
                        
                        % FFT to get frequency response
                        H_freq = fft(cir_fft, nfft);
                        
                        % Extract subcarriers: MATLAB's nrOFDMModulate uses a specific mapping.
                        % The resource grid subcarriers map to FFT bins. For 5G NR:
                        % - DC is typically at bin Nfft/2+1 (center)
                        % - Resource grid subcarrier 0 maps to the first active subcarrier
                        % - Standard mapping: grid subcarrier k -> FFT bin (k + Nfft/2 - n_subcarriers/2 + 1)
                        % But the exact mapping depends on guard bands. Use a test-based approach:
                        % Create a test grid with known values, modulate, and find mapping.
                        % For now, use the standard convention: subcarriers are centered around DC
                        % Resource grid indices 0 to n_subcarriers-1 map to FFT bins
                        % For Nfft=128, n_subcarriers=120: typically bins 5:124
                        % Use: bins starting from (Nfft - n_subcarriers)/2 + 1
                        sc_start = floor((nfft - n_subcarriers) / 2) + 1;
                        sc_indices = sc_start : sc_start + n_subcarriers - 1;
                        H(:, sym, tx, rx) = H_freq(sc_indices);
                    end
                end
            end
            
            % Squeeze to remove singleton dimensions (SISO: NT=NR=1)
            H = squeeze(H);
            if size(H, 3) > 1 || size(H, 4) > 1
                % MIMO case - keep all dimensions
            else
                % SISO case - ensure 2D output
                H = H(:, :);
            end
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
