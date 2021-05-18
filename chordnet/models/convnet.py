import torch
import torch.nn as nn
import torch.nn.functional as F

import pytorch_lightning as pl

from chordnet.models.spectconv import SpectrumConv, build_spectrum_sequential
from chordnet.models.model import Model

import pdb

class ConvNet(Model):
    def __init__(self, data_props, L=3, H=5):
        super().__init__(data_props)

        self.data_props = data_props
        quality_n = data_props.encoding.quality_n()
        octave_n = data_props.octave_n
        bin_n = data_props.bin_n

        spectra_args = {'octave_n': octave_n, 'bin_n': bin_n}
        self.root_net = \
            build_spectrum_sequential(1, 1,         L, H, nn.Tanh(), **spectra_args)
        self.quality_net = \
            build_spectrum_sequential(1, quality_n, L, H, nn.Tanh(), **spectra_args)

        self.quality_linear = nn.Linear(quality_n * octave_n * bin_n, quality_n)

        self.loss_func = nn.NLLLoss()

    def forward(self, x):
        batch_n = x.shape[0]

        x = x.unsqueeze(1)  # Add single channel to input

        roots = self.root_net(x).reshape(batch_n, -1)
        qualities = self.quality_net(x).reshape(batch_n, -1)

        # Sum adjacent bins for same note
        roots = roots.reshape(batch_n, 12 * self.data_props.octave_n,
                              self.data_props.bin_n // 12).sum(2)
        # Sum across octaves
        roots = roots.reshape(batch_n, self.data_props.octave_n, 12).sum(1)

        roots = F.log_softmax(roots)
        qualities = F.log_softmax(self.quality_linear(qualities))

        return roots, qualities, torch.tensor(0.0)

    def configure_optimizers(self):
        optimizer = torch.optim.Adam(self.parameters(), lr=1e-3)
        return optimizer
