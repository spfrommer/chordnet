import torch
from torch.utils.data import DataLoader, random_split
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
from chordnet.models.mlp import MLP
from chordnet.models.mlp_rnn import MLPRNN
from chordnet.models.convnet import ConvNet
from chordnet.models.chordnet import ChordNet

import pdb


def setup_tensorboard():
    tensorboard_dir = dirs.out_path('default', 'version_0')
    if file_utils.directory_exists(tensorboard_dir):
        file_utils.clear_directory(tensorboard_dir)

    # Use threading so tensorboard is automatically closed on process end
    command = 'tensorboard --bind_all --port 6006 '\
              '--logdir {} > /dev/null --window_title {} 2>&1'\
              .format(tensorboard_dir, socket.gethostname())
    t = threading.Thread(target=os.system, args=(command,))
    t.start()

    print('Launching tensorboard on http://localhost:6006')


data_choices = ['gen', 'bill-mm-tiny', 'bill-mm7-tiny',
                'bill-mm-small', 'bill-mm7-small', 'bill-mm-all', 'bill-mm7-all']

@click.command()

@click.option('--model', default='chord',
              type=click.Choice(['mlp', 'mlprnn', 'conv', 'chord'], case_sensitive=False))
@click.option('--epochs', default=1000)

@click.option('--data', default=None, type=click.Choice(data_choices, case_sensitive=False))

@click.option('--fetch_data/--no_fetch_data', default=True,
              help="If false, don't fetch data, just write the metadata.")

@click.option('--file_filter', default='') # Can be something like -drums for generated

@click.option('--augment/--no_augment', default=False)

def run(model, epochs, data, fetch_data, file_filter, augment):
    if data is not None and fetch_data and not click.confirm('Overwrite data with fetch?'):
        return

    dataset = ChordDataModule(DatasetType.from_string(data), fetch_data,
                              file_filter=file_filter, augment=augment,
                              batch_size=1, split=[0.5, 0.5, 0.0])

    # Tuples of network, gpus
    models = {'mlp': (MLP(dataset.props), 0),
              'mlprnn': (MLPRNN(dataset.props), 0),
              'conv': (ConvNet(dataset.props), 0),
              'chord': (ChordNet(dataset.props), 0)}

    model, gpus = models[model]

    warnings.filterwarnings('ignore')
    setup_tensorboard()
    logger = TensorBoardLogger(dirs.out_path(), 'default', version=0, default_hp_metric=False)

    gradient_clip_val = model.gradient_clip_val if hasattr(model, 'gradient_clip_val') else 0
    print(f'Got gradient clip value: {gradient_clip_val}')

    checkpoint_dir = dirs.out_path('checkpoints')
    file_utils.create_empty_directory(checkpoint_dir)
    checkpoint_callback = ModelCheckpoint(monitor='val_loss', dirpath=checkpoint_dir)

    trainer = pl.Trainer(max_epochs=epochs, logger=logger, num_sanity_val_steps=0, gpus=gpus,
                         gradient_clip_val=gradient_clip_val, callbacks=[checkpoint_callback])
    trainer.fit(model, dataset)

    if len(dataset.test_data) > 0:
        trainer.test()


if __name__ == "__main__":
    run()
