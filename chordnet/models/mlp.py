import torch
import torch.nn as nn
import torch.nn.functional as F

import pytorch_lightning as pl

from chordnet.models.model import Model

import pdb

def build_sequential(in_length, out_length, L, H):
    if L <= 1:
        return nn.Sequential(nn.Linear(in_length, out_length), nn.LogSoftmax(dim=1))

    modules = [nn.Linear(in_length, H), nn.ReLU()]
    for _ in range(L - 2):
        modules.append(nn.Linear(H, H))
        modules.append(nn.ReLU())
    modules.append(nn.Linear(H, out_length))
    modules.append(nn.LogSoftmax(dim = 1))

    return nn.Sequential(*modules)


class MLP(Model):
    def __init__(self, data_props, L=5, H=100):
        super().__init__(data_props)

        spectra_len = data_props.octave_n * data_props.bin_n
        root_n = data_props.encoding.root_n()
        quality_n = data_props.encoding.quality_n()

        self.root_net = build_sequential(spectra_len, root_n, L, H)
        self.quality_net = build_sequential(spectra_len, quality_n, L, H)

        self.loss_func = nn.NLLLoss()

    def forward(self, x):
        return self.root_net(x), self.quality_net(x), torch.tensor(0.0)

    def configure_optimizers(self):
        return torch.optim.Adam(self.parameters(), lr=1e-3)
