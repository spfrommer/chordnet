import torch
import torch.nn as nn
import torch.nn.functional as F

import pytorch_lightning as pl

import matplotlib.pyplot as plt

from chordnet.models.spectconv import SpectrumConv, build_spectrum_sequential
from chordnet.models.model import Model
from chordnet.utils import music_utils

import pdb

class ChordNet(Model):
    def __init__(self, data_props):
        super().__init__(data_props)

        self.data_props = data_props
        spectra_args = {'octave_n': data_props.octave_n, 'bin_n': data_props.bin_n}

        nonlin = nn.Tanh()

        # How far to look backwards / forwards for prediction. [0] is just the current chord
        self.history_inclusions = list(range(-5, 6))
        # self.history_inclusions = [0]
        in_channels = len(self.history_inclusions)

        self.attention_net = build_spectrum_sequential(in_channels, in_channels,
            L=2, H=20, nonlin=nonlin, flatten_last=True, **spectra_args)

        self.root_net = build_spectrum_sequential(
            in_channels, 1, L=2, H=200, nonlin=nonlin, octave_n=1, bin_n=data_props.bin_n)

        quality_hidden = 100
        self.quality_net = nn.Sequential(
            nn.Linear(12 * in_channels, quality_hidden),
            nonlin,
            nn.Linear(quality_hidden, quality_hidden),
            nonlin,
            nn.Linear(quality_hidden, data_props.encoding.quality_n())
        )

        self.loss_func = nn.NLLLoss()

    def forward(self, x):
        seq_n = x.shape[0]

        # Take x and add channels corresponding to past / future chords
        rolls = [self.roll_zeros_seq(x, roll_amount) for roll_amount in self.history_inclusions]
        x = torch.flip(torch.stack(rolls, 1), (1, ))

        x = self.attention_net(x)

        # Sum across octaves
        x = x.reshape(seq_n, len(self.history_inclusions), self.data_props.octave_n, 12).sum(2)

        roots = self.root_net(x).reshape(seq_n, -1)
        roots = F.log_softmax(roots, dim=1)
        _, roots_selected = torch.max(roots, dim=1)

        # The magic: shift the chord such that the root is in the zero position
        # Creates quality invariance to root shifts

        # Roll all elements of each history by the root of the middle chord
        x = self.roll_dim(x, tuple((-roots_selected).tolist()), dim=0).reshape(seq_n, -1)

        qualities = F.log_softmax(self.quality_net(x))

        reg = torch.tensor(0.0, device=self.device)

        return roots, qualities, reg

    def roll_dim(self, tensor, roll_amounts, dim):
        rolled = []
        for t, roll_amount in zip(torch.unbind(tensor, dim), roll_amounts):
            rolled.append(torch.roll(t, roll_amount, -1))
        return torch.stack(rolled, dim)

    def roll_zeros_seq(self, tensor, roll_amount):
        # Roll along the zeroeth dim and fill in zeros
        output = torch.roll(tensor, shifts=roll_amount, dims=0)
        if roll_amount > 0:
            output[:roll_amount] = 0
        elif roll_amount < 0:
            output[roll_amount:] = 0
        return output


    def configure_optimizers(self):
        # params = [{'params': self.root_net.parameters(), 'lr': 1e-4, 'weight_decay': },
                  # {'params': self.quality_net.parameters(), 'lr': 1e-4, 'weight_decay': 1e-4}]
        # params.append({'params': self.attention_net.parameters(),
                       # 'lr': 1e-4, 'weight_decay': 1e-4})

        optimizer = torch.optim.Adam(self.parameters(), lr=1e-4, weight_decay=0)
        scheduler = torch.optim.lr_scheduler.LambdaLR(optimizer, lambda epoch: 0.97 ** epoch)

        # return optimizer, scheduler
        return [optimizer], [scheduler]

    def training_epoch_end(self, outputs):
        super().training_epoch_end(outputs)

        plt.switch_backend('agg')

        if len(self.root_net) == 1:
            fig = plt.figure()
            plt.plot(self.root_net[0].conv.weight.squeeze().cpu().detach().numpy())
            plt.ylim([-2, 2])
            plt.xticks(ticks=range(12), labels=music_utils.roots)
            plt.grid()

            self.logger.experiment.add_figure('Root filter', fig, self.current_epoch)
