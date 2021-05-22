from enum import Enum

class DatasetType(Enum):
    GENERATED                   = 1
    BILLBOARD_MAJMIN_TINY       = 2
    BILLBOARD_MAJMIN7_TINY      = 3
    BILLBOARD_MAJMIN_SMALL      = 4
    BILLBOARD_MAJMIN7_SMALL     = 5
    BILLBOARD_MAJMIN_ALL        = 6
    BILLBOARD_MAJMIN7_ALL       = 7

    @classmethod
    def from_string(cls, type_string):
        return {
            'gen': cls.GENERATED,
            'bill-mm-tiny': cls.BILLBOARD_MAJMIN_TINY,
            'bill-mm7-tiny': cls.BILLBOARD_MAJMIN7_TINY,
            'bill-mm-small': cls.BILLBOARD_MAJMIN_SMALL,
            'bill-mm7-small': cls.BILLBOARD_MAJMIN7_SMALL,
            'bill-mm-all': cls.BILLBOARD_MAJMIN_ALL,
            'bill-mm7-all': cls.BILLBOARD_MAJMIN7_ALL
        }.get(type_string)
