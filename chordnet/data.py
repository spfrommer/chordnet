import torch
from torch import Tensor
from torch.utils.data import DataLoader, TensorDataset, random_split
from torch.nn.utils.rnn import pad_sequence
from scipy.io import wavfile as wav
from scipy.fftpack import dct
import numpy as np
import copy
import zipfile
import re
import sys
import pickle
import pytorch_lightning as pl
import pychord
import random
from tabulate import tabulate
import librosa
from typing import List, Dict

from dataclasses import dataclass

from chordnet.utils import dirs, file_utils, music_utils, annotation_utils
from chordnet.utils.data_utils import DatasetType
from chordnet.utils.music_utils import Chord, ChordEncoding
from chordnet.utils.tempo import TempoDetector

import pdb

@dataclass
class DataProperties():
    encoding: ChordEncoding
    octave_n: int
    bin_n: int # Bins per octave

class ListDataset(torch.utils.data.Dataset):
    def __init__(self, signals: List[Tensor], targets: List[Tensor], metadatas: List[Dict]):
        assert len(signals) == len(targets) == len(metadatas)
        self.signals = signals
        self.targets = targets
        self.metadatas = metadatas

    def __getitem__(self, index):
        return self.signals[index], self.targets[index], self.metadatas[index]

    def __len__(self):
        return len(self.signals)

def pad_collate(batch):
    signals = [data[0] for data in batch]
    targets = [data[1] for data in batch]
    metadatas = [data[2] for data in batch]

    signals = pad_sequence(signals, batch_first=True, padding_value=music_utils.PADDED)
    targets = pad_sequence(targets, batch_first=True, padding_value=music_utils.PADDED)

    return signals, targets, metadatas

class ChordDataModule(pl.LightningDataModule):
    MISTIMING_THRESHOLD = 0.5 # Fraction of beat duration we're okay mistiming
    START_OCTAVE = -4

    def __init__(self, dataset_type, fetch_data, file_filter='',
                 augment=False, batch_size=1, split=[0.60, 0.25, 0.15]):
        super().__init__()

        if dataset_type is None:
            metadata = self.read_metadata()
            if metadata is None:
                raise RuntimeError('Must specify data type!')
            dataset_type = metadata['dataset_type']
            print(f'Loaded dataset type: {dataset_type}')
            self.load_dataset = False
        else:
            if not fetch_data:
                # Make sure right metadata is there if previous fetch was aborted or similar
                self.write_metadata({'dataset_type': dataset_type})

            self.load_dataset = fetch_data


        encodings = {
            DatasetType.GENERATED:                  music_utils.GeneratedEncoding(),
            DatasetType.BILLBOARD_MAJMIN_TINY:      music_utils.BillboardMajMinEncoding(),
            DatasetType.BILLBOARD_MAJMIN7_TINY:     music_utils.BillboardMajMin7Encoding(),
            DatasetType.BILLBOARD_MAJMIN_SMALL:     music_utils.BillboardMajMinEncoding(),
            DatasetType.BILLBOARD_MAJMIN7_SMALL:    music_utils.BillboardMajMin7Encoding(),
            DatasetType.BILLBOARD_MAJMIN_ALL:       music_utils.BillboardMajMinEncoding(),
            DatasetType.BILLBOARD_MAJMIN7_ALL:      music_utils.BillboardMajMin7Encoding()
        }

        self.dataset_type = dataset_type
        self.props = DataProperties(encodings[dataset_type], octave_n=7, bin_n=24)
        self.file_filter = file_filter
        self.augment = augment
        self.batch_size = batch_size
        self.split = split


    def prepare_data(self):
        if self.load_dataset:
            print('Fetching dataset...')
            dataset_file = {
                DatasetType.GENERATED:                  'generated.zip',
                DatasetType.BILLBOARD_MAJMIN_TINY:      'billboard-tiny.zip',
                DatasetType.BILLBOARD_MAJMIN7_TINY:     'billboard-tiny.zip',
                DatasetType.BILLBOARD_MAJMIN_SMALL:     'billboard-small.zip',
                DatasetType.BILLBOARD_MAJMIN7_SMALL:    'billboard-small.zip',
                DatasetType.BILLBOARD_MAJMIN_ALL:       'billboard-all.zip',
                DatasetType.BILLBOARD_MAJMIN7_ALL:      'billboard-all.zip'
            }.get(self.dataset_type)

            dataset_zip = dirs.root_path('misc', 'data_zips', dataset_file)

            file_utils.create_empty_directory(dirs.data_path())
            with zipfile.ZipFile(dataset_zip, 'r') as zip_ref:
                zip_ref.extractall(dirs.data_path())

            print('Parsing spectra...')
            self.parse_all_spectra()

            print('Writing metadata...')
            self.write_metadata({'dataset_type': self.dataset_type})

    def setup(self, stage=None):
        """Load the chord classification dataset.

        Computes the following to produce the train / val / test datasets:
            signals: N x 12 tensor. Frequency decomposition of the audio.
                0th index corresponds to A, last index is Ab (see music_utils).
            targets: N x 2 tensor. First index along second dimension is the root,
                numbered 0-12, with A=0 and Ab=12. The second index is the quality,
                as also given in music_utils.
        """

        signals, targets, metadatas = [], [], []

        files = file_utils.files_with_extension(dirs.data_path(), 'pickle')
        files = [f for f in files if (self.file_filter in f)]

        for chord_file in files:
            with open(dirs.data_path(chord_file), 'rb') as f:
                data = pickle.load(f)

            if data['annotation_mistiming'] > self.MISTIMING_THRESHOLD:
                continue

            signals.append(data['chromas'])
            targets.append(data['chords'])

            metadatas.append({'beats': data['beats'], 'annotations': data['annotations'],
                              'song': file_utils.remove_extension(chord_file)})

        # Convert signals / targets from 2d list to list of sequence tensors of shape T x *
        signals = [np.stack(s) / np.max(np.stack(s)) for s in signals]
        signals = [torch.from_numpy(s).type(torch.FloatTensor) for s in signals]
        targets = [torch.tensor(t) for t in targets]

        all_data = ListDataset(signals, targets, metadatas)

        assert len(self.split) == 3
        train_size = int(self.split[0] * len(all_data))
        val_size = int(self.split[1] * len(all_data))
        test_size = len(all_data) - train_size - val_size

        self.train_data, self.val_data, self.test_data = \
            random_split(all_data, [train_size, val_size, test_size])

        if self.augment:
            self.train_data = self.augment_dataset(self.train_data, range(-6, 6))
        else:
            self.train_data = self.augment_dataset(self.train_data, [0])
        self.val_data = self.augment_dataset(self.val_data, [0])
        self.test_data = self.augment_dataset(self.test_data, [0])

        # self.report_data_stats()

        loader = self.train_dataloader()

    def augment_dataset(self, dataset, shifts):
        if len(dataset) == 0:
            return dataset

        datasets = []
        bins_per_note = self.props.bin_n // 12

        for shift in shifts:
            new_signals, new_targets, new_metadatas = [], [], []

            for (signal, target, metadata) in dataset:
                # chromas are augmented in one octave both directions
                # Get correct octave_n length chroma for the shift
                def shift_chord(chord, shift):
                    root, quality = chord[0].item(), chord[1].item()
                    if self.props.encoding.qualities[0] == 'N' and quality == 0:
                        return (root, quality)

                    if root == music_utils.NO_ENCODING:
                        return (root, quality)

                    return ((root - shift) % 12, quality)


                new_signals.append(signal[:, self.props.bin_n + shift * bins_per_note :
                                            -self.props.bin_n + shift * bins_per_note])
                new_targets.append(torch.tensor([shift_chord(chord, shift) for chord in target]))

                metadata = copy.deepcopy(metadata)
                metadata['song'] += f' ({shift:+})'
                new_metadatas.append(metadata)

            datas = list(zip(new_signals, new_targets, new_metadatas))
            random.shuffle(datas)
            new_signals, new_targets, new_metadatas = zip(*datas)

            datasets.append(
                ListDataset(list(new_signals), list(new_targets), list(new_metadatas)))

        return torch.utils.data.ConcatDataset(datasets)


    def train_dataloader(self):
        return DataLoader(self.train_data, batch_size=self.batch_size,
                          num_workers=0, collate_fn=pad_collate)

    def val_dataloader(self):
        return DataLoader(self.val_data, batch_size=1, num_workers=0,
                          collate_fn=pad_collate)

    def test_dataloader(self):
        return DataLoader(self.test_data, batch_size=1, num_workers=0,
                          collate_fn=pad_collate)


    def report_data_stats(self):
        print("\n========================================")

        train_size, val_size, test_size = \
            len(self.train_data), len(self.val_data), len(self.test_data)
        print(f'Data: {train_size} (train), {val_size} (val), {test_size} (test)\n')

        def extract_counts(data):
            # Add 1 for chords with no encoding ("X")
            root_counts = torch.zeros(self.props.encoding.root_n() + 1, dtype=torch.long)
            quality_counts = torch.zeros(self.props.encoding.quality_n() + 1, dtype=torch.long)
            for (_, chords, _) in data:
                for chord in chords:
                    assert chord[0] != music_utils.PADDED
                    if chord[0] == music_utils.NO_ENCODING:
                        root_counts[-1] += 1
                        quality_counts[-1] += 1
                    else:
                        if not self.props.encoding.int_to_quality(chord[1]) == 'N':
                            root_counts[chord[0]] += 1
                        quality_counts[chord[1]] += 1
            return root_counts.tolist(), quality_counts.tolist()

        train_root_counts, train_quality_counts = extract_counts(self.train_data)
        val_root_counts,   val_quality_counts   = extract_counts(self.val_data)
        test_root_counts,  test_quality_counts  = extract_counts(self.test_data)

        roots_headers = [''] + self.props.encoding.roots + ['X']
        roots_table = [['Train'] + train_root_counts, ['Valid'] + val_root_counts,
                       ['Test'] + test_root_counts]
        print(tabulate(roots_table, headers=roots_headers) + '\n')

        qualities_headers = [''] + self.props.encoding.qualities + ['X']
        qualities_table = [['Train'] + train_quality_counts, ['Valid'] + val_quality_counts,
                           ['Test'] + test_quality_counts]
        print(tabulate(qualities_table, headers=qualities_headers))

        print("========================================")


    def write_metadata(self, metadata):
        file_utils.ensure_created_directory(dirs.data_path())
        with open(dirs.data_path('metadata'), 'wb') as file:
            return pickle.dump(metadata, file)

    def read_metadata(self):
        try:
            with open(dirs.data_path('metadata'), 'rb') as file:
                return pickle.load(file)
        except FileNotFoundError:
            return None

        return None


    def parse_all_spectra(self):
        """Parses all wav files in the data directory and outputs the spectra pickle files."""
        wavs = file_utils.files_with_extension(dirs.data_path(), 'wav')
        for wav_file in wavs:
            parsers = {
                DatasetType.GENERATED:                  self.parse_spectra_generated,
                DatasetType.BILLBOARD_MAJMIN_TINY:      self.parse_spectra_song,
                DatasetType.BILLBOARD_MAJMIN7_TINY:     self.parse_spectra_song,
                DatasetType.BILLBOARD_MAJMIN_SMALL:     self.parse_spectra_song,
                DatasetType.BILLBOARD_MAJMIN7_SMALL:    self.parse_spectra_song,
                DatasetType.BILLBOARD_MAJMIN_ALL:       self.parse_spectra_song,
                DatasetType.BILLBOARD_MAJMIN7_ALL:      self.parse_spectra_song
            }

            parsed = parsers[self.dataset_type](dirs.data_path(wav_file))
            try:
                parsed = parsers[self.dataset_type](dirs.data_path(wav_file))
            except KeyboardInterrupt:
                sys.exit()
            except Exception as e:
                print(e)
                print(f'Got exception on parsing {wav_file} -- skipping')
                continue

            parsed_name = file_utils.change_extension(wav_file, 'pickle')
            with open(dirs.data_path(parsed_name), 'wb') as out:
                pickle.dump(parsed, out)

    def parse_spectra_generated(self, wav_file):
        f0, data = wav.read(wav_file)
        wav_file = file_utils.file_name(wav_file)

        octaves = list(range(self.START_OCTAVE - 1,
                             self.START_OCTAVE + self.props.octave_n + 1))
        chroma = self.parse_spectra_window(data, f0, octaves, t_start=0.0, win=0.5)
        chroma = chroma.flatten()

        chord_name = file_utils.remove_extension(wav_file)

        chord = Chord.create_from_string(re.split('-|\.', chord_name)[0], self.props.encoding)

        return { 'chromas': [chroma], 'chords': [chord.to_tuple()],
                 'beats': [], 'annotations': [(chord.to_tuple(), 0.0, 3.0)],
                 'annotation_mistiming': 0.0}

    def parse_spectra_song(self, wav_file, beat_info=None, read_annotations=True):
        """Parse beat and spectral information from a wav_file.

        Arguments:
            wav_file: the file path.
            beat_info: tuple (bpm, beats) if tempo has already been detected.
            read_annotations: whether to match annotation data against the beats.

        Returns:
            Dict of parsed data.
        """
        f0, data = wav.read(wav_file)
        last_time = data.shape[0] / f0;

        detector = TempoDetector()
        detector.uploadSong(wav_file)
        bpm, beats_orig = detector.detectBPM('RNN')
        # TODO: sometimes tempo detector spits out beat past end of song...
        beats_orig = [beat for beat in beats_orig.tolist() if beat < last_time]
        beats = [0.0] + beats_orig + [last_time]

        wav_file = file_utils.file_name(wav_file)

        if read_annotations:
            annotations = annotation_utils.load_annotations(
                wav_file[:4], self.dataset_type, self.props.encoding)

        chromas, chords = [], []
        for (current_beat, next_beat) in zip(beats[:-1], beats[1:]):
            beat_len = next_beat - current_beat
            # Add one extra low and high octave for data augmentation later
            octaves = list(range(self.START_OCTAVE - 1,
                                 self.START_OCTAVE + self.props.octave_n + 1))
            chroma = self.parse_spectra_repeated(
                data, f0, octaves, t_start=current_beat, win=beat_len)
            chromas.append(chroma.flatten())

            if read_annotations:
                chords.append(annotation_utils.best_match(annotations, current_beat, next_beat))

        if read_annotations:
            def get_closest_beat(t):
                return min([abs(b - t) for b in beats])
            beat_dists = [get_closest_beat(annotation[1]) for annotation in annotations]
            annotation_mistiming = sum(beat_dists) / len(beat_dists)
            annotation_mistiming *= 60 / bpm # Convert to fraction of beat length

            print(f'Parsed: {wav_file}, annotation mistiming {annotation_mistiming:.2f}')
        else:
            print(f'Parsed: {wav_file}')

        data = { 'chromas': chromas, 'beats': beats_orig }
        if read_annotations:
            data['chords'] = chords
            data['annotations'] = annotations
            data['annotation_mistiming'] = annotation_mistiming

        return data


    def parse_spectra_repeated(self, data, f0, octaves, t_start=0.0, win=3.0):
        """Samples the window with many random subwindows to ensure that all notes are covered.

        Not guaranteed to work, but likelihood is high.

        Parameters:
            data: numpy array of audio data
            f0: sampling frequency
            octaves: list of octaves to parse relative to A440, e.g. [-3, -2, -1, 0, 1, 2]
            t_start: start time of spectra parsing
            win: length of spectra extraction window

        Returns:
            Matrix of size [n_oct x 12], splitting the spectrum into multiple octaves.
        """

        subwindow_n = 10

        spectra = self.parse_spectra_window(data, f0, octaves, t_start, win)
        for i in range(subwindow_n):
            rand_1, rand_2 = random.uniform(0, win), random.uniform(0, win)
            fact = 5 # Higher drives the edges of the subwindow closer to teh window
            rand_start = min(rand_1, rand_2) / fact
            rand_win = max(rand_1, rand_2) - rand_start + \
                       (win - max(rand_1, rand_2)) * (fact - 1) / fact
            assert rand_win < win and rand_win > win / 2
            spectra += self.parse_spectra_window(data, f0, octaves, t_start+rand_start, rand_win)

        spectra /= (subwindow_n + 1)

        return spectra


    def parse_spectra_window(self, data, f0, octaves, t_start=0.0, win=3.0):
        """
        Parses the segment of audio and returns the frequency decomposition.

        Parameters:
            data: numpy array of audio data
            f0: sampling frequency
            octaves: list of octaves to parse relative to A440, e.g. [-3, -2, -1, 0, 1, 2]
            t_start: start time of spectra parsing
            win: length of spectra extraction window

        Returns:
            Matrix of size [n_oct x 12], splitting the spectrum into multiple octaves.
        """

        # If stereo, make mono
        if len(data.shape) == 2:
            dataM = data[:,0] + data[:,1]
        else:
            dataM = data

        dataM = dataM[int(f0 * t_start):]

        # Choose length of subwindow (too slow to freq decomp whole window at a time)
        # subwin = win/3 #seconds
        subwin = win

        win_samps = int(win*f0)
        subwin_samps = int(subwin*f0)

        # Choose how many windows
        Nwins = 1
        Nsubwins = int(np.floor(win/subwin))

        # Frequencies in Hz which correspond to DCT coefficient index
        fs = np.arange(0,subwin_samps, 1)*f0/(2*subwin_samps)

        # Store DCT Coefficients here
        FofT = np.zeros((subwin_samps,Nwins))

        i_skip = 0

        # Iterate through file by windows
        for i in range(Nwins):
            # Iterate through subwindows
            for j in range(Nsubwins):
                start_i = (i+i_skip)*win_samps + j*subwin_samps
                stop_i = (i+i_skip)*win_samps + (j+1)*subwin_samps
                if stop_i <= len(dataM):
                    FofT[:,i] += dct(dataM[start_i:stop_i], norm='ortho')/Nsubwins

        # Power
        PofT = FofT**2 #Had log before

        ts = np.arange(0,win*(Nwins + 1),win)

        # Now iterate through octaves to bin frequencies by note and visualize spectrograms more easily
        A = 440 #Hz, A above middle C
        note_names = ['A','Bb','B','C','C#','D','Eb','E','F','F#','G','Ab','A']

        # Z:= num substones. Subtones := number of divisions of a semitone (made this up). Z = 1 for normal binning
        assert self.props.bin_n % 12 == 0
        Z = self.props.bin_n // 12

        # Store discretized notes per octave
        subtonesofToct = np.zeros((len(octaves),(len(note_names)-1)*Z,Nwins))

        for i, octv in enumerate(octaves):
            # Frequencies in Hz for half step pitches
            notes = A*2**octv*np.power(2**(1/12), np.arange(0,12+1,1))
            # Frequencies in Hz for subtones, which define the bin boundaries
            subtones = A*2**octv*np.power(2**(1/12), np.arange(1/(2*Z), 12 + 1/(2*Z), 1/Z))
            # Convert frequencies into DCT coefficient indices
            note_is = notes*(2*subwin_samps/f0)
            note_is = note_is.astype(int)
            subtone_is = subtones*(2*subwin_samps/f0)
            subtone_is = subtone_is.astype(int)

            low_i = note_is[0]
            high_i = note_is[-1]
            fs_oct = fs[low_i:high_i]
            PofT_oct = PofT[low_i:high_i,:]

            # Bin by note, take averages
            for j in range(12 * Z):
                if j == 0:
                    # Get the notes in the ranges between A and A 1/(2Z) sharp, and G 1/(2Z) sharp and A
                    notepow = np.vstack((PofT[low_i:subtone_is[0],:], PofT[subtone_is[-1]:high_i, :]))
                else:
                    notepow = PofT[subtone_is[j-1]:subtone_is[j]]

                len_notepow, _ = np.shape(notepow)

                if len_notepow != 0:
                    subtonesofToct[i, j, :] += np.sum(notepow, axis = 0)/len_notepow

        return np.log(1 + subtonesofToct.squeeze())
