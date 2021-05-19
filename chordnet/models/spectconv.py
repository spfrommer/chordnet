import torch
import torch.nn as nn
import torch.nn.functional as F

import pdb

class SpectrumConv(nn.Module):
    def __init__(self, in_channels, out_channels, octave_n=1, bin_n=12, stride=1):
        super().__init__()
        padding_mode = 'circular' if octave_n == 1 else 'zeros'
        self.conv = nn.Conv1d(in_channels, out_channels, bin_n, stride=stride,
                              padding=bin_n // 2, padding_mode=padding_mode, bias=False)

    def forward(self, x):
        old_shape = x.shape
        x = self.conv(x)
        x = x[:, :, 1:] # Last dimension had even length so must chop off one entry
        return x

def build_spectrum_sequential(in_channels, out_channels, L, H, nonlin,
                              octave_n=1, bin_n=12, flatten_last=False):
    # flatten_last will make the output have 12 bins / octave
    spectra_args = {'octave_n': octave_n, 'bin_n': bin_n}

    out_stride = bin_n // 12 if flatten_last else 1

    if L == 1:
        return nn.Sequential(SpectrumConv(in_channels, out_channels,
                                          stride=out_stride, **spectra_args))

    modules = [SpectrumConv(in_channels, H, **spectra_args), nonlin]
    for _ in range(L - 2):
        modules.append(SpectrumConv(H, H, **spectra_args))
        modules.append(nonlin)

    modules.append(SpectrumConv(H, out_channels, stride=out_stride, **spectra_args))

    return nn.Sequential(*modules)

