import torch
from torch.utils.data import DataLoader, random_split
import numpy as np
import os
import socket
import threading
import warnings
import click

import pytorch_lightning as pl
from pytorch_lightning.loggers import TensorBoardLogger
from pytorch_lightning.callbacks import ModelCheckpoint

from chordnet.data import ChordDataModule, DatasetType, DataProperties
from chordnet.utils import dirs, file_utils
from chordnet.utils.music_utils import Chord
from chordnet.models.mlp import MLP
from chordnet.models.mlp_rnn import MLPRNN
from chordnet.models.convnet import ConvNet
from chordnet.models.chordnet import ChordNet

import pdb


@click.command()

@click.argument('checkpoint')
@click.argument('song')

def run(checkpoint, song):
    model = ChordNet.load_from_checkpoint(checkpoint)

    # Create a dummy data module, we're only using the parse_spectra_song function
    data = ChordDataModule(DatasetType.BILLBOARD_MAJMIN7_ALL, False)
    song_data = data.parse_spectra_song(song, read_annotations=False)

    bin_n = model.data_props.bin_n
    spectra = torch.from_numpy(np.stack(song_data['chromas'])).type(torch.FloatTensor)
    spectra = spectra[:, bin_n:-bin_n]

    roots, qualities, _ = model(spectra)

    _, root_classes = torch.max(roots, 1)
    _, quality_classes = torch.max(qualities, 1)

    chords = []
    for (root, quality) in zip(root_classes, quality_classes):
        chords.append(Chord(root, quality).string_encoding(model.data_props.encoding))

    annot = [str(c) for c in zip([0] + song_data['beats'], chords)]
    print('\n'.join(annot))


if __name__ == "__main__":
    run()
