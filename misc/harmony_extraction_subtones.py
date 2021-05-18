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
subwin = win/3 #seconds # was win/3

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

# Z:= num substones. Subtones := number of divisions of a semitone (made this up). Z = 1 for normal binning
Z = 2

# This is where discretized "subtones" are stored. Subtones := number of divisions of a semitone (made this up).
subtonesofT = np.zeros(((len(note_names)-1)*Z,Nwins))

# Store discretized notes per octave
subtonesofToct = np.zeros((len(octvs),(len(note_names)-1)*Z,Nwins))

plt.close('all')
fig, ax = plt.subplots(ncols = len(octvs), figsize = (17,5))
fig1, ax1 = plt.subplots(ncols = len(octvs), figsize = (17,5))

for i, octv in enumerate(octvs):
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
    # Plot spectrogram for an octave
    im = ax[i].pcolormesh(ts, fs_oct, PofT_oct, cmap = 'plasma')
    # Log scale is nice since pitches follow exponential relation in Hz
    ax[i].set_yscale('log')
    ax[i].set_title('Octave {}: A = {:.0f}'.format(octv, 440*2**octv))
    ax[i].minorticks_off()

    # Bin by note, take averages
    for j in range(12*Z):
        if j == 0:
        #Get the notes in the ranges between A and A 1/(2Z) sharp, and G 1/(2Z) sharp and A
            notepow = np.vstack((PofT[low_i:subtone_is[0],:], PofT[subtone_is[-1]:high_i, :]))
        else:
            notepow = PofT[subtone_is[j-1]:subtone_is[j]]

        len_notepow, _ = np.shape(notepow)

        if len_notepow != 0:
            subtonesofT[j,:] += np.sum(notepow, axis = 0)/len_notepow
            subtonesofToct[i, j, :] += np.sum(notepow, axis = 0)/len_notepow
        else:
            pass
            # raise Exception("Frequency resolution is too low for this number of subtones. Decrease Z or increase subwin.")

    # Spectra of DCT frequencies (no binning)
    ax[i].yaxis.set_major_formatter(FormatStrFormatter('%.0f'))
    ax[i].set_yticks(notes)
    ax[i].set_yticklabels(note_names, rotation = 'horizontal')
    ax[i].set_xlabel('Time (s)')
    cbar = fig.colorbar(im, ax = ax[i])
    cbar.formatter.set_powerlimits((0,0))
    fig.suptitle('DCT Frequencies by Octave')

    # Binning for several octaves
    ax1[i].pcolormesh(ts[:], range(12*Z + 1), subtonesofToct[i,:,:], cmap = 'plasma')
    #ax1[i].yaxis.set_major_formatter(FormatStrFormatter('%.0f'))
    #ax1[i].set_yticks(np.arange(0,len(note_names)-1) + 0.5)
    #ax1[i].set_yticklabels(note_names[:-1], rotation = 'horizontal')
    ax1[i].set_xlabel('Time (s)')
    ax1[i].set_title('Octave {}: A = {:.0f}'.format(octv, 440*2**octv))
    cbar1 = fig1.colorbar(im, ax = ax1[i])
    cbar1.formatter.set_powerlimits((0,0))
    fig1.suptitle('Binned Pitches by Octave')


# Finally, plot binned pitch
fig2, ax2 = plt.subplots()
im2 = ax2.pcolormesh(ts[:], range(12*Z + 1), subtonesofT[:,:], cmap = 'plasma')
#ax2.set_yticks(np.arange(0,len(note_names)-1) + 0.5)
#ax2.set_yticklabels(note_names[:-1], rotation = 'horizontal')
ax2.set_xlabel('Time (s)')
ax2.set_ylabel('Pitch')
ax2.set_title('Binned Pitches: Octaves {}'.format(str(octvs)))

cbar2 = fig.colorbar(im2, ax = ax2)
cbar2.formatter.set_powerlimits((0,0))

plt.show()
