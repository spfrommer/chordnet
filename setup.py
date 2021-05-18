from setuptools import setup, find_namespace_packages

setup(
    name='chordnet',
    packages=find_namespace_packages(include=['chordnet.*']),
    version='0.1',
    install_requires=[
        # Tempo detection
        'pydub',
        'PyWavelets',
        'cython',
        'mido',
        'madmom',
        'plotly',
        'librosa',
        # Harmony
        'sklearn',
        'torchtestcase',
        'matplotlib',
        'tabulate',
        'click',
        'pychord',
        'numpy',
        'scipy',
        'torch',
        'pytorch-lightning'
    ])
