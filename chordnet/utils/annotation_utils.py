import operator

import chordnet.data as data
from chordnet.utils import dirs
from chordnet.utils.music_utils import *

def load_annotations(song_id, dataset_type, chord_encoding):
    lab_files = {
        data.DatasetType.BILLBOARD_MAJMIN_TINY:    'majmin.lab',
        data.DatasetType.BILLBOARD_MAJMIN7_TINY:   'majmin7.lab',
        data.DatasetType.BILLBOARD_MAJMIN_SMALL:   'majmin.lab',
        data.DatasetType.BILLBOARD_MAJMIN7_SMALL:  'majmin7.lab',
        data.DatasetType.BILLBOARD_MAJMIN_ALL:     'majmin.lab',
        data.DatasetType.BILLBOARD_MAJMIN7_ALL:    'majmin7.lab'
    }

    annotations_file = dirs.data_path(
        'annotations-mirex', song_id, lab_files[dataset_type])

    with open(annotations_file, 'r') as f:
        annotation_lines = f.read().splitlines();
        annotations = []
        for line in annotation_lines:
            if len(line) == 0:
                continue

            parts = line.split('\t')

            chord_string = parts[2]
            if chord_string == 'N':
                chord = Chord.create_no_chord(chord_encoding)
            elif chord_string == 'X':
                chord = Chord.create_no_encoding()
            else:
                chord_string = standardize_chord(chord_string).replace(':', '')
                chord = Chord.create_from_string(chord_string, chord_encoding)

            annotations.append((chord.to_tuple(), float(parts[0]), float(parts[1])))

    return annotations

def standardize_chord(chord_string):
    # Standardizes chord of the form A:maj. This means convert things like Fb -> E
    # so chordify can recognize it.
    roots = ['A', 'Bb', 'B', 'C', 'Db', 'D',
             'Eb', 'E', 'F', 'Gb', 'G', 'Ab']

    root, quality = chord_string.split(':')

    if root.endswith('b') and (root not in roots):
        root = roots[roots.index(root[:1]) - 1]

    return root + quality


def best_match(annotations, start_time, end_time):
    candidates = {}
    for annotation in annotations:
        chord = annotation[0]
        annotation_interval = (annotation[1], annotation[2])

        new_overlap = interval_overlap((start_time, end_time), annotation_interval)
        overlap = candidates.get(chord, 0)
        candidates[chord] = overlap + new_overlap

    # Return the annotation with the maximum overlap
    return max(candidates.items(), key=operator.itemgetter(1))[0]

def interval_overlap(a, b):
    return max(0, min(a[1], b[1]) - max(a[0], b[0]))
