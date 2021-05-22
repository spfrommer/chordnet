import torch
import torch.nn as nn
import torch.nn.functional as F

import itertools
import numpy as np
from sklearn.metrics import confusion_matrix

import pytorch_lightning as pl

import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Rectangle
from matplotlib import cm
import tabulate

from chordnet.utils.music_utils import Chord
from chordnet.utils import list_utils, music_utils

import pdb


class Model(pl.LightningModule):
    """Children need to override forward and set self.loss_func.

    forward
    Args:
        signal: T x (octave_n * bin_n) Tensor. T is the number of subdivisions in the audio
        sequence (generally number of beats). For each time subdivision, we get a copy of the
        spectra.

    Returns:
        roots: T x root_n Tensor.
        qualities: T x quality_n Tensor.
        regularizer: scalar Tensor.

    loss_func
    Matches signature of something like torch.nn.NLLLoss()
    """

    def __init__(self, data_props):
        super().__init__()
        self.data_props = data_props
        self.save_hyperparameters()

    def training_step(self, batch, batch_idx):
        return self.compute_losses(batch, 'loss')

    def validation_step(self, batch, batch_idx):
        return self.compute_losses(batch, 'val_loss')

    def test_step(self, batch, batch_idx):
        return self.compute_losses(batch, 'test_loss')

    def compute_losses(self, batch, loss_string):
        signals, targets = self.remove_padding(batch[0], batch[1])
        metadatas = batch[2]

        vars = []
        root_preds, quality_preds, regularizers, root_losses, quality_losses = [], [], [], [], []
        for signal, target, metadata in zip(signals, targets, metadatas):
            # vars for this particular batch
            vb = {}
            vb['root_pred'], vb['quality_pred'], vb['regularizer'] = self.forward(signal)

            has_encoding = (target[:, 0] != music_utils.NO_ENCODING).nonzero(as_tuple=True)[0]
            root_pred, quality_pred = \
                vb['root_pred'][has_encoding, :], vb['quality_pred'][has_encoding, :]
            root_true, quality_true = target[has_encoding, 0], target[has_encoding, 1]
            vb['quality_pred_proc'], vb['quality_true_proc'] = quality_pred, quality_true

            if self.data_props.encoding.qualities[0] == 'N':
                has_root = (quality_true != 0).nonzero(as_tuple=True)[0]
                root_pred = root_pred[has_root, :]
                root_true = root_true[has_root]
            vb['root_pred_proc'], vb['root_true_proc'] = root_pred, root_true

            if torch.numel(root_pred) > 0:
                vb['root_loss'] = self.loss_func(root_pred, root_true)
                vb['root_acc'] = self.compute_accuracy(root_pred, root_true)
            else:
                # We might have zero elements if all chord qualities are X or N
                scalar_to_tensor = lambda x: torch.tensor(x).to(self.device)
                vb['root_loss'], vb['root_acc'] = scalar_to_tensor(0.0), scalar_to_tensor(1.0)

            vb['quality_loss'] = self.loss_func(quality_pred, quality_true)
            vb['quality_acc'] = self.compute_accuracy(quality_pred, quality_true)

            vb['chords_pred'] = self.get_chord_strings(
                torch.max(vb['root_pred'], 1)[1], torch.max(vb['quality_pred'], 1)[1])
            vb['chords_true'] = self.get_chord_strings(target[:, 0], target[:, 1])

            vb['beats'] = metadata['beats']
            vb['song'] = metadata['song']

            vb['signal'] = signal
            vb['target'] = target

            vars.append(vb)

        vars = list_utils.list_dict_swap(vars)

        for var in ['root_loss', 'quality_loss', 'regularizer']:
            vars[var] = sum(vars[var])

        for var in ['root_acc', 'quality_acc']:
            vars[var] = sum(vars[var]) / len(vars[var])

        vars[loss_string] = vars['root_loss'] + vars['quality_loss'] + vars['regularizer']

        # For the model checkpointing
        self.log(loss_string, vars[loss_string])

        return vars

    def remove_padding(self, signals_padded, targets_padded):
        """Removes padding from list of signal and target tensors."""
        signals, targets = [], []
        for signal, target in zip(signals_padded, targets_padded):
            padding_locs = (target[:, 0] == music_utils.PADDED).nonzero().flatten().tolist()
            padding_start = target.shape[0] if len(padding_locs) == 0 else padding_locs[0]

            signals.append(signal[:padding_start, :])
            targets.append(target[:padding_start, :])

        return signals, targets

    def compute_accuracy(self, pred, targets):
        return self.get_correct_entries(pred, targets).sum() / (pred.shape[0])

    def get_correct_entries(self, pred, targets):
        _, pred_class = torch.max(pred, 1)
        return (pred_class == targets)

    def get_chord_strings(self, root_classes, quality_classes):
        # root_classes and quality_classes are 1D tensors
        chords = []
        for (root, quality) in zip(root_classes, quality_classes):
            chords.append(Chord(root, quality).string_encoding(self.data_props.encoding))
        return chords


    def training_epoch_end(self, outputs):
        self.log_outputs(outputs, 'Train')

    def validation_epoch_end(self, outputs):
        for epoch_out in outputs:
            epoch_out['loss'] = epoch_out.pop('val_loss')

        self.log_outputs(outputs, 'Valid')

    def log_outputs(self, outputs, type_string):
        experiment = self.logger.experiment
        losses = self.calc_means(outputs, 'loss')
        experiment.add_scalars(f"Loss/{type_string}", losses, self.current_epoch)

        accs = self.calc_means(outputs, 'acc')
        experiment.add_scalars(f"Accuracies/{type_string}", accs, self.current_epoch)

        self.make_song_figures(outputs, type_string)
        self.make_spectra_figures(outputs, type_string)
        self.make_confusion_matrices(outputs, type_string)

    def calc_means(self, outputs, in_key):
        return { key: self.calc_mean(outputs, key) \
                 for key in outputs[0].keys() if in_key in key}

    def calc_mean(self, outputs, key):
        return torch.stack([x[key] for x in outputs]).mean()

    def make_song_figures(self, outputs, type_string):
        experiment = self.logger.experiment

        songs_n = 5
        fields = ['beats', 'chords_pred', 'chords_true', 'song']
        plot_data = self.zip_output_fields(outputs, fields)[:songs_n]

        for (i, (beat_seq, pred_seq, true_seq, song)) in enumerate(plot_data):
            # Number of chords per row (1 extra column for True / Pred
            cols_n = min(8, len(true_seq))
            rows_n = min((len(true_seq) // cols_n), 6)

            beat_seq = ['0.00'] + [str(round(beat, 2)) for beat in beat_seq]

            fig, axes = plt.subplots(rows_n, 1)
            if not isinstance(axes, np.ndarray):
                axes = [axes]
            for row in range(rows_n):
                table = [['Beat'] + beat_seq[row * cols_n : (row + 1) * cols_n],
                         ['True'] + true_seq[row * cols_n : (row + 1) * cols_n],
                         ['Pred'] + pred_seq[row * cols_n : (row + 1) * cols_n]]
                axes[row].axis('tight')
                axes[row].axis('off')
                axes[row].table(cellText=table, loc='center')

            fig.suptitle(song)

            experiment.add_figure(f'A. Chords {type_string}/{i}', fig, self.current_epoch)


    def make_spectra_figures(self, outputs, type_string):
        experiment = self.logger.experiment

        songs_n = 5
        fields = ['beats', 'chords_pred', 'chords_true', 'song', 'signal']
        plot_data = self.zip_output_fields(outputs, fields)[:songs_n]

        for (i, (beat_seq, pred_seq, true_seq, song, signal)) in enumerate(plot_data):
            signal = signal.cpu()
            start_n = 0 if len(beat_seq) <= 1 else 1
            chord_n = 10 + start_n
            beat_seq, pred_seq, true_seq, signal = ([0.0] + beat_seq)[start_n:chord_n+1], \
                pred_seq[start_n:chord_n], true_seq[start_n:chord_n], signal[start_n:chord_n]

            # If data has no beats (single chord), give arbitrary end time
            if len(beat_seq) <= 1:
                beat_seq = [0.0, 1.0]

            fig, ax = plt.subplots(1, 1)
            ax.tick_params(width=2)
            fig.set_figwidth(10)
            fig.set_figheight(15)

            plasma = cm.get_cmap('plasma', 1000)
            plasma_vals = plasma(np.linspace(0, 1, 100000))
            plasma_vals[0, :] = np.array([0, 0, 0, 1]) # All true zeros become black
            plasma = ListedColormap(plasma_vals)
            
            ax.pcolormesh(beat_seq, range(signal.shape[1] + 1), signal.T.numpy(), cmap=plasma)

            ax.set_xticks(beat_seq)

            # Space out alternating y axis note names
            note_names = self.data_props.encoding.roots * self.data_props.octave_n
            for j, name in enumerate(note_names):
                if j % 2 == 1:
                    note_names[j] = name + '     '

            subdivisions = self.data_props.bin_n // 12
            ax.set_yticks([tick*subdivisions + 0.5 for tick in range(len(note_names))])
            ax.set_yticklabels(labels=note_names, rotation='horizontal')

            plt.tick_params(axis='x', pad=25)

            table = [true_seq, pred_seq]
            col_widths = np.asarray(beat_seq[1:]) - np.asarray(beat_seq[:-1])
            col_widths /= (beat_seq[-1] - beat_seq[0])

            ax.table(cellText=table, loc='bottom', cellLoc='center', colWidths=col_widths)

            self.chord_overlay(beat_seq, true_seq, ax, color=(0.0, 1.0, 0.0, 0.8))
            self.chord_overlay(beat_seq, pred_seq, ax, color=(1.0, 0.0, 0.0, 0.5))

            fig.suptitle(song)
            fig.tight_layout()

            experiment.add_figure(f'B. Spectra {type_string}/{i}', fig, self.current_epoch)

    def chord_overlay(self, beat_seq, chords, ax, color='r'):
        subdivisions = self.data_props.bin_n // 12

        for i, chord in enumerate(chords):
            chord = Chord.create_from_string(chord, self.data_props.encoding)

            notes = [(n * subdivisions) % self.data_props.bin_n for n in chord.notes(self.data_props.encoding)]
            notes_octaves = []
            for j in range(self.data_props.octave_n):
                notes_octaves += [n + j * self.data_props.bin_n for n in notes]

            for note in notes_octaves:
                ax.add_patch(Rectangle((beat_seq[i], note), beat_seq[i+1] - beat_seq[i], 1,
                    linewidth=2, edgecolor=color, facecolor='none'))


    def make_confusion_matrices(self, outputs, type_string):
        experiment = self.logger.experiment

        fields = ['root_pred_proc', 'root_true_proc', 'quality_pred_proc', 'quality_true_proc']
        data = self.zip_output_fields(outputs, fields, zero_shift=True)

        root_n = self.data_props.encoding.root_n()
        qual_n = self.data_props.encoding.quality_n()
        root_confusion, quality_confusion = np.zeros((root_n, root_n)), np.zeros((qual_n, qual_n))

        for (root_pred, root_true, quality_pred, quality_true) in data:
            if torch.numel(root_pred) > 0:
                root_pred = torch.max(root_pred, 1)[1]
                # Rows correspond to true labels, columns are predicted
                root_confusion += confusion_matrix(root_true.cpu(), root_pred.cpu(),
                                                   labels=list(range(root_n)))

            quality_pred = torch.max(quality_pred, 1)[1]
            quality_confusion += confusion_matrix(quality_true.cpu(), quality_pred.cpu(),
                                                  labels=list(range(qual_n)))


        fig = self.plot_confusion_matrix(root_confusion, self.data_props.encoding.roots)
        experiment.add_figure(f'C. Confusion Root/{type_string}', fig, self.current_epoch)

        fig = self.plot_confusion_matrix(quality_confusion, self.data_props.encoding.qualities)
        experiment.add_figure(f'D. Confusion Quality/{type_string}', fig, self.current_epoch)

    def plot_confusion_matrix(self, cm, classes, normalize=True):
        # Adapted from deeplizard.com
        if normalize:
            cm = cm.astype('float') / cm.sum()

        fig, ax = plt.subplots(1, 1)
        ax.tick_params(width=2)
        fig.set_figwidth(10)
        fig.set_figheight(10)

        cmap = plt.cm.get_cmap('plasma')

        plt.imshow(cm, interpolation='nearest', cmap=cmap)
        plt.colorbar()
        tick_marks = np.arange(len(classes))
        plt.xticks(tick_marks, classes, rotation=45)
        plt.yticks(tick_marks, classes)

        fmt = '.2f' if normalize else 'd'
        thresh = cm.max() / 2.
        for i, j in itertools.product(range(cm.shape[0]), range(cm.shape[1])):
            plt.text(j, i, format(cm[i, j], fmt), horizontalalignment="center",
                     color="white" if cm[i, j] < thresh else "black")

        plt.tight_layout()
        plt.ylabel('True label')
        plt.xlabel('Predicted label')

        return fig


    def zip_output_fields(self, outputs, fields, ignore_augment=True, zero_shift=True):
        not_augmented = list_utils.flatten_top([o['song'] for o in outputs])
        if zero_shift:
            not_augmented = [i for (i, na) in enumerate(not_augmented) if '(+0)' in na]
        else:
            not_augmented = [i for (i, na) in enumerate(not_augmented)]

        output_fields = []
        for field in fields:
            field_outputs = list_utils.flatten_top([o[field] for o in outputs])
            if ignore_augment:
                output_fields.append([field_outputs[i] for i in not_augmented])
            else:
                output_fields.append(field_outputs)

        return list(zip(*output_fields))


    def configure_optimizers(self):
        optimizer = torch.optim.SGD(self.parameters(), lr=1e-3, weight_decay=1e-3)
        return optimizer
