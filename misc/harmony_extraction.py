# -*- coding: utf-8 -*-
"""
Created on Thu Oct 22 12:57:16 2020

@author: bhask
"""
import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile as wav
from scipy.fftpack import dct, fft
from scipy import signal
from matplotlib.ticker import FormatStrFormatter

import pdb


# Import wav file
#f0, data = wav.read("samples/fly me mix normal.wav")
# f0, data = wav.read("samples/asin.wav")
# f0, data = wav.read("samples/Bbmaj-nodrums.wav")
# f0, data = wav.read("../data/Gmaj-drums.wav")
f0, data = wav.read("samples/0984 Barbara Lewis - Hello Stranger.wav")

# If stereo, make mono
if len(data.shape) == 2:
    dataM = data[:,0] + data[:,1]
else:
    dataM = data

# Skip until first beat
# t_skip = 0.81 #seconds
t_skip = 0.64 #seconds

dataM = dataM[int(f0*t_skip):]

# Get frequency decomp for every 0.5 seconds of the track
M = len(dataM)
secs = M/f0

# Choose window length
# win = 4*60/110 #seconds
win = 0.64 #seconds #was 1

# Choose length of subwindow (too slow to freq decomp whole window at a time)
# subwin = win/3 #seconds
subwin = win #seconds

win_samps = int(win*f0)
subwin_samps = int(subwin*f0)

# How many windows in the file
print('Max windows: {}'.format(int(M/win_samps)))

# Choose how many windows
Nwins = 3
Nsubwins = int(np.floor(win/subwin))

# Frequencies in Hz which correspond to DCT coefficient index
#fs = np.arange(0,win_samps, 1)*f0/(2*win_samps)
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
        FofT[:,i] += dct(dataM[start_i:stop_i], norm='ortho')/Nsubwins

# Power
PofT = FofT**2 #Had log before

ts = np.arange(0,win*(Nwins + 1),win)

# Now iterate through octaves to bin frequencies by note and visualize spectrograms more easily
A = 440 #Hz, A above middle C
octvs = [-3,-2,-1,0,1] #Could be expanded
note_names = ['A','Bb','B','C','C#','D','Eb','E','F','F#','G','Ab','A']

# This is where discretized notes are stored
notesofT = np.zeros((len(note_names)-1,Nwins))

# Store discretized notes per octave
notesofToct = np.zeros((len(octvs),len(note_names)-1,Nwins))

plt.close('all')
fig, ax = plt.subplots(ncols = len(octvs), figsize = (17,5))
fig1, ax1 = plt.subplots(ncols = len(octvs), figsize = (17,5))

for i, octv in enumerate(octvs):
    # Frequencies in Hz for half step pitches
    notes = A*2**octv*np.power(2**(1/12), np.arange(0,12+1,1))
    # Frequencies in Hz for quartertones, which define the bin boundaries
    qtones = A*2**octv*np.power(2**(1/12), np.arange(0.5,11.5+1,1))
    # Convert frequencies into DCT coefficient indices
    note_is = notes*(2*subwin_samps/f0)
    note_is = note_is.astype(int)
    qtone_is = qtones*(2*subwin_samps/f0)
    qtone_is = qtone_is.astype(int)

    low_i = note_is[0]
    high_i = note_is[-1]
    fs_oct = fs[low_i:high_i]
    PofT_oct = PofT[low_i:high_i,:]
    # Plot spectrogram for an octave
    im = ax[i].pcolormesh(ts, fs_oct, PofT_oct, cmap = 'plasma')
    # Log scale is nice since pitches follow exponential relation in Hz
    ax[i].set_yscale('log')
    ax[i].set_title('Octave {}: A = {:.0f}'.format(octv, 440*2**octv))
    ax[i].minorticks_off()

    # Bin by note, take averages
    for j in range(len(note_names)-1):
        if j == 0:
        #Get the notes in the ranges between A and A half sharp, and G half sharp and A
            notepow = np.vstack((PofT[low_i:qtone_is[0],:], PofT[qtone_is[-1]:high_i, :]))
            len_notepow, _ = np.shape(notepow)
            notesofT[j,:] += np.sum(notepow, axis = 0)/len_notepow
            notesofToct[i, j, :] = np.sum(notepow, axis = 0)/len_notepow
        else:
            notepow = PofT[qtone_is[j-1]:qtone_is[j]]
            len_notepow, _ = np.shape(notepow)
            notesofT[j,:] += np.sum(notepow, axis = 0)/len_notepow
            notesofToct[i, j, :] += np.sum(notepow, axis = 0)/len_notepow

    # Spectra of DCT frequencies (no binning)
    ax[i].yaxis.set_major_formatter(FormatStrFormatter('%.0f'))
    ax[i].set_yticks(notes)
    ax[i].set_yticklabels(note_names, rotation = 'horizontal')
    ax[i].set_xlabel('Time (s)')
    cbar = fig.colorbar(im, ax = ax[i])
    cbar.formatter.set_powerlimits((0,0))
    fig.suptitle('DCT Frequencies by Octave')

    # Binning for several octaves
    ax1[i].pcolormesh(ts[:], range(len(note_names)), notesofToct[i,:,:], cmap = 'plasma')
    ax1[i].yaxis.set_major_formatter(FormatStrFormatter('%.0f'))
    ax1[i].set_yticks(np.arange(0,len(note_names)-1) + 0.5)
    ax1[i].set_yticklabels(note_names[:-1], rotation = 'horizontal')
    ax1[i].set_xlabel('Time (s)')
    ax1[i].set_title('Octave {}: A = {:.0f}'.format(octv, 440*2**octv))
    cbar1 = fig1.colorbar(im, ax = ax1[i])
    cbar1.formatter.set_powerlimits((0,0))
    fig1.suptitle('Binned Pitches by Octave')


# Finally, plot binned pitch
fig2, ax2 = plt.subplots()
im2 = ax2.pcolormesh(ts[:], range(len(note_names)), notesofT[:,:], cmap = 'plasma')
ax2.set_yticks(np.arange(0,len(note_names)-1) + 0.5)
ax2.set_yticklabels(note_names[:-1], rotation = 'horizontal')
ax2.set_xlabel('Time (s)')
ax2.set_ylabel('Pitch')
ax2.set_title('Binned Pitches: Octaves {}'.format(str(octvs)))

cbar2 = fig.colorbar(im2, ax = ax2)
cbar2.formatter.set_powerlimits((0,0))

plt.show()
