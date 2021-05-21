import pychord

from typing import List

PADDED = -1
NO_ENCODING = -2

class Chord():
    def __init__(self, root: int, quality: int):
        """Creates a chord capable of representing a MIREX annotation.

        Arguments:
            root: the root of the chord (integer value is specified by an encoding).
            quality: the quality of the chord (integer value is specified by an encoding).
        """
        self.root = root
        self.quality = quality
        self.no_encoding = root == NO_ENCODING

    @staticmethod
    def create_valid(root: int, quality: int):
        return Chord(root, quality)

    @staticmethod
    def create_no_encoding():
        return Chord(NO_ENCODING, NO_ENCODING)

    @staticmethod
    def create_no_chord(encoding):
        assert encoding.qualities[0] == 'N'
        return Chord(0, 0)

    @staticmethod
    def create_from_string(string, encoding):
        if string == 'X':
            return Chord.create_no_encoding()

        if string == 'N':
            return Chord.create_no_chord(encoding)

        string = Chord.to_pychord_string(string)

        chord = pychord.Chord(string)
        root = encoding.note_to_int(chord.root)

        quality = str(chord.quality)
        quality = Chord.from_pychord_string(quality)

        quality = encoding.quality_to_int(quality)
        return Chord(root, quality)

    def notes(self, encoding):
        if self.root == NO_ENCODING or encoding.int_to_quality(self.quality) == 'N':
            return []

        chord = pychord.Chord(Chord.to_pychord_string(self.string_encoding(encoding)))
        notes = chord.components(visible=False)
        notes = [n + 3 for n in notes] # pychord makes C the 0 note, we want A
        return notes

    def is_valid(self):
        return not self.no_encoding

    def to_tuple(self):
        return (self.root, self.quality)

    def string_encoding(self, encoding):
        if self.root == NO_ENCODING:
            return 'X'

        if encoding.int_to_quality(self.quality) == 'N':
            return 'N'

        return encoding.int_to_note(self.root) + encoding.int_to_quality(self.quality)

    @staticmethod
    def to_pychord_string(chord: str):
        chord = chord.replace('min7', 'm7')
        return chord

    @staticmethod
    def from_pychord_string(chord: str):
        chord = chord.replace('m7', 'min7')
        return chord


class ChordEncoding():
    def __init__(self, roots: List[str], qualities: List[str]):
        self.roots = roots
        self.qualities = qualities


    def root_n(self) -> int:
        return len(self.roots)

    def quality_n(self) -> int:
        return len(self.qualities)


    # ALL INDICES START AT ONE
    def int_to_note(self, root_index: int) -> str:
        return self.roots[root_index]

    def note_to_int(self, root: str) -> int:
        if root.endswith('#'):
            return self.roots.index(root[:1]) + 1
        if root.endswith('b') and (root not in self.roots):
            return self.roots.index(root[:1]) - 1

        return self.roots.index(root)

    def int_to_quality(self, quality_index: int) -> str:
        return self.qualities[quality_index]

    def quality_to_int(self, quality: str) -> int:
        return self.qualities.index(quality)


class GeneratedEncoding(ChordEncoding):
    def __init__(self):
        roots = ['A', 'Bb', 'B', 'C', 'Db', 'D',
                 'Eb', 'E', 'F', 'Gb', 'G', 'Ab']
        qualities = ['maj', 'min', 'maj7', 'dim']
        super().__init__(roots, qualities)

class BillboardMajMinEncoding(ChordEncoding):
    def __init__(self):
        roots = ['A', 'Bb', 'B', 'C', 'Db', 'D',
                 'Eb', 'E', 'F', 'Gb', 'G', 'Ab']
        qualities = ['N', 'maj', 'min']
        super().__init__(roots, qualities)

class BillboardMajMin7Encoding(ChordEncoding):
    def __init__(self):
        roots = ['A', 'Bb', 'B', 'C', 'Db', 'D',
                 'Eb', 'E', 'F', 'Gb', 'G', 'Ab']
        qualities = ['N', 'maj', 'min', 'maj7', 'min7', '7']
        super().__init__(roots, qualities)
