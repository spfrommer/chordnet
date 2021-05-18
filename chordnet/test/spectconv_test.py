import unittest

import torch
import torch.nn as nn
import torchtestcase as ttc

from chordnet.models.spectconv import SpectrumConv, build_spectrum_sequential
from chordnet.data import DataProperties

import pdb

class SpectConvTest(ttc.TorchTestCase):
    def test_circular(self):
        bin_n = 12

        conv = SpectrumConv(1, 1, octave_n=1, bin_n=bin_n, stride=1)

        with torch.no_grad():
            conv.conv.weight.fill_(0)
            conv.conv.weight[0, 0, 0] = 1

        data = torch.arange(bin_n).type(torch.FloatTensor).reshape(1, 1, -1)

        self.assertEqual(torch.roll(data, bin_n // 2 - 1), conv(data))

        # Permutation equivariance
        self.assertEqual(torch.roll(conv(data), 1), conv(torch.roll(data, 1)))

    def test_zeros(self):
        octave_n, bin_n = 3, 12

        conv = SpectrumConv(1, 1, octave_n=octave_n, bin_n=bin_n, stride=1)

        with torch.no_grad():
            conv.conv.weight.fill_(0)
            conv.conv.weight[0, 0, 0] = 1

        data = torch.arange(2 * bin_n).type(torch.FloatTensor).reshape(1, 1, -1)
        data[0, 0, :bin_n // 2] = 0
        data[0, 0, -bin_n // 2 + 1:] = 0

        correct_out = torch.roll(data, bin_n // 2 - 1)

        self.assertEqual(correct_out, conv(data))

    def test_circular_stride(self):
        bin_n = 24

        conv = SpectrumConv(1, 1, octave_n=1, bin_n=bin_n, stride=2)

        with torch.no_grad():
            for i in range(bin_n):
                conv.conv.weight[0, 0, i] = i % 2

        data = torch.arange(bin_n).type(torch.FloatTensor).reshape(1, 1, -1)
        for i in range(bin_n):
            if i % 2 == 1:
                data[0, 0, i] = 0

        self.assertEqual(torch.zeros(1, 1, 12), conv(data))

    def test_zeros_stride(self):
        octave_n, bin_n = 2, 24

        conv = SpectrumConv(1, 1, octave_n=octave_n, bin_n=bin_n, stride=2)

        with torch.no_grad():
            for i in range(bin_n):
                conv.conv.weight[0, 0, i] = i % 2

        data = torch.arange(octave_n * bin_n).type(torch.FloatTensor).reshape(1, 1, -1)
        for i in range(octave_n * bin_n):
            if i % 2 == 1:
                data[0, 0, i] = 0

        self.assertEqual(torch.zeros(1, 1, bin_n), conv(data))

    def test_sequential_circular(self):
        octave_n, bin_n = 1, 12

        net = build_spectrum_sequential(1, 1, L=5, H=20, nonlin=nn.ReLU(),
            flatten_last=False, octave_n=octave_n, bin_n=bin_n)

        data = torch.arange(octave_n * bin_n).type(torch.FloatTensor).reshape(1, 1, -1)
        for i in range(octave_n * bin_n):
            self.assertEqual(net(data).roll(i), net(data.roll(i)))

if __name__ == '__main__':
    unittest.main()
