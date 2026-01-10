# SISO OFDM Channel Generator

A MATLAB-based tool for generating OFDM channel estimation datasets for 5G NR systems. This project creates paired channel data (ideal and LS estimates) suitable for training and evaluating machine learning models for channel estimation.

## Citation

This code was used to generate the dataset for:

> **AdaFortiTran: An Adaptive Transformer Model for Robust OFDM Channel Estimation**  
> Accepted at IEEE ICC 2025, Montreal, Canada  
> [https://ieeexplore.ieee.org/document/11160810](https://ieeexplore.ieee.org/document/11160810)

If you use this code, please cite the above paper.

## Requirements

- MATLAB R2020a or later
- 5G Toolbox
- Communications Toolbox

## Project Structure

```
OFDMChannelGenerator/
├── generate_full_dataset.m     # Master script for complete dataset generation
├── generate_train_and_val.m    # Generate training and validation datasets
├── generate_snr_test_set.m     # Generate test set varying SNR
├── generate_ds_test_set.m      # Generate test set varying delay spread
├── generate_mds_test_set.m     # Generate test set varying max Doppler shift
├── helpers/
│   ├── OFDMChannelEstimator.m  # Main channel generator class
│   ├── bilinear_interp.m       # Bilinear interpolation for LS estimates
│   └── organize_by_param.m     # Utility to reorganize saved data
└── baselines/
    ├── lmmse.m                 # LMMSE channel estimation baseline
    ├── get_corr_from_path.m    # Correlation extraction utility
    └── get_corr_stats.m        # Correlation statistics utility
```

## Quick Start

1. Open MATLAB and navigate to the `OFDMChannelGenerator` directory
2. Run the full pipeline to replicate the paper dataset:

```matlab
>> generate_full_dataset    % Generates complete dataset (144k samples)
```

Or run individual scripts for custom generation:
```matlab
>> generate_train_and_val    % Creates train/ and val/ folders with data
```

## Dataset Generation Scripts

### `generate_full_dataset.m` (Recommended for Paper Replication)

Master script that generates the complete dataset used in the [AdaFortiTran paper (ICC 2025)](https://ieeexplore.ieee.org/document/11160810). Runs all generation steps and organizes test sets automatically.

**What it generates:**
| Dataset | Samples | Description |
|---------|---------|-------------|
| Training | 100,000 | Random SNR, DS, MDS from configured ranges |
| Validation | 10,000 | Random SNR, DS, MDS from configured ranges |
| SNR Test | 12,000 | Fixed DS=200ns, MDS=500Hz, varying SNR (0:5:25 dB) |
| DS Test | 12,000 | Fixed SNR=10dB, MDS=600Hz, varying DS (50:50:300 ns) |
| MDS Test | 10,000 | Fixed SNR=10dB, DS=100ns, varying MDS (200:200:1000 Hz) |
| **Total** | **144,000** | |

**Output structure after running:**
```
OFDMChannelGenerator/
├── train/                    # 100k training samples
├── val/                      # 10k validation samples
└── test/
    ├── SNR_test_set/
    │   ├── SNR_0/            # 2k samples at SNR=0dB
    │   ├── SNR_5/            # 2k samples at SNR=5dB
    │   └── ...
    ├── DS_test_set/
    │   ├── DS_50/            # 2k samples at DS=50ns
    │   ├── DS_100/           # 2k samples at DS=100ns
    │   └── ...
    └── MDS_test_set/
        ├── DOP_200/          # 2k samples at MDS=200Hz
        ├── DOP_400/          # 2k samples at MDS=400Hz
        └── ...
```

### `generate_train_and_val.m`
Generates training and validation datasets with randomly sampled channel parameters.

- **Output:** `train/` and `val/` folders
- **Parameters varied:** SNR, delay spread, max Doppler shift (randomly sampled)

### `generate_snr_test_set.m`
Generates a test set with fixed delay spread and Doppler shift, varying only SNR.

- **Output:** `test/SNR_test_set/`
- **Use case:** Evaluate model performance across different noise levels

### `generate_ds_test_set.m`
Generates a test set with fixed SNR and Doppler shift, varying only delay spread.

- **Output:** `test/DS_test_set/`
- **Use case:** Evaluate model performance across different channel delay characteristics

### `generate_mds_test_set.m`
Generates a test set with fixed SNR and delay spread, varying only max Doppler shift.

- **Output:** `test/MDS_test_set/`
- **Use case:** Evaluate model performance across different mobility scenarios

## Output Format

Each generated `.mat` file contains:
- `H`: A 120×14×2 array where:
  - `H(:,:,1)` = Ideal (perfect) channel estimate
  - `H(:,:,2)` = Least squares channel estimate at pilot positions
- `var_hat`: Estimated noise variance

File naming convention:
```
{index}_SNR-{snr}_DS-{delay_spread}_DOP-{doppler}_N-{pilot_spacing}_{delay_profile}.mat
```

## Configuration

You can modify the following parameters in each script:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `N` | Pilot spacing (subcarriers between pilots) | 3 |
| `sample_rate` | OFDM sample rate in Hz | 3.84e6 |
| `delay_profile` | 3GPP channel model (TDL-A, TDL-B, etc.) | TDL-A |
| `SNR` | Signal-to-noise ratio range (dB) | 0:5:25 |
| `delay_spread` | RMS delay spread range (ns) | 25:25:300 |
| `max_dop_shift` | Max Doppler shift range (Hz) | 50:50:1000 |

## Symmetric Pilot Placement

The `OFDMChannelEstimator` automatically calculates the optimal offset for symmetric pilot placement across subcarriers. This ensures the first pilot is at the same distance from the start of the grid as the last pilot is from the end.

### How it works

With 120 subcarriers and pilot spacing `N`, pilots are placed at positions:
```
(offset + 1), (offset + 1 + N), (offset + 1 + 2N), ...
```

For symmetric placement, we need:
```
(num_subcarriers - 1 - 2*offset) mod N == 0
```

Rearranging:
```
2*offset mod N == (num_subcarriers - 1) mod N
```

### Examples (120 subcarriers)

| N | Calculation | Symmetric Offset | Achievable? |
|---|-------------|------------------|-------------|
| 3 | 119 mod 3 = 2, solve 2*offset mod 3 = 2 | **1** | ✓ |
| 5 | 119 mod 5 = 4, solve 2*offset mod 5 = 4 | **2** | ✓ |
| 7 | 119 mod 7 = 0, solve 2*offset mod 7 = 0 | **0** | ✓ |
| 4 | 119 mod 4 = 3 (odd), 2*offset always even | 0 (fallback) | ✗ |

**Note:** Perfect symmetry is only achievable when `N` is odd, or when `(num_subcarriers - 1) mod N` is even. If not achievable, a warning is issued and offset defaults to 0.

### Manual calculation

You can also compute the offset manually:
```matlab
offset = OFDMChannelEstimator.computeSymmetricOffset(N);           % Uses default 120 subcarriers
offset = OFDMChannelEstimator.computeSymmetricOffset(N, num_sc);   % Custom subcarrier count
```

## Organizing Data by Parameter

The `helpers/organize_by_param.m` utility reorganizes generated dataset files into subfolders based on a specific parameter value.

### Usage

1. Open `helpers/organize_by_param.m`
2. Set the configuration:
```matlab
source_folder = 'test/DS_test_set';  % Folder containing .mat files
organize_by = 'DS';                   % Parameter to group by: 'SNR', 'DS', or 'DOP'
```
3. Run the script

### Example

Before (flat structure):
```
test/DS_test_set/
├── 1_SNR-10_DS-50_DOP-600_N-3_TDL-A.mat
├── 2_SNR-10_DS-50_DOP-600_N-3_TDL-A.mat
├── 1_SNR-10_DS-100_DOP-600_N-3_TDL-A.mat
└── ...
```

After running with `organize_by = 'DS'`:
```
test/DS_test_set/
├── DS_50/
│   ├── 1_SNR-10_DS-50_DOP-600_N-3_TDL-A.mat
│   └── 2_SNR-10_DS-50_DOP-600_N-3_TDL-A.mat
├── DS_100/
│   └── 1_SNR-10_DS-100_DOP-600_N-3_TDL-A.mat
└── ...
```

This is useful for loading data by parameter value during model training or evaluation.

## Author

Berkay Guler