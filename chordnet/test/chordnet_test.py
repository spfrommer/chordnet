import unittest

import torch
import torchtestcase as ttc

from chordnet.models.chordnet import ChordNet
from chordnet.data import DataProperties
from chordnet.utils.music_utils import BillboardMajMin7Encoding

import pdb

class ChordNetTest(ttc.TorchTestCase):
    def test_chordnet_equivariant(self):
        octave_n, bin_n = 5, 12
        bins_per_note = bin_n // 12
        data_props = DataProperties(BillboardMajMin7Encoding(), octave_n, bin_n)
        net = ChordNet(data_props)

        def rand_input():
            x = torch.rand(bin_n * octave_n)
            x[:bin_n] = 0
            x[-bin_n:] = 0
            return x.unsqueeze(0)

        for _ in range(10):
            x = rand_input()
            root, qual, _ = net(x)
            # for i in range(-bin_n, bin_n + 1, bins_per_note):
            for i in [1]:
                root_shift, qual_shift, _ = net(x.roll(i))

                pdb.set_trace()

                self.assertEquals(root.roll(i // bins_per_note), root_shift)
                self.assertEquals(qual, qual_shift)


if __name__ == '__main__':
    unittest.main()
