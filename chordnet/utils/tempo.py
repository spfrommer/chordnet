import numpy as np
import os
import pydub
from pydub import AudioSegment
from scipy.io.wavfile import read
import math
import pywt
from scipy import signal
import madmom
from madmom.features.beats import RNNBeatProcessor, BeatTrackingProcessor, MultiModelSelectionProcessor
import librosa
import plotly.graph_objects as go
import time

########################################################################################################################
class TempoDetector():

    def __init__(self):
        self.songData = None #the actual intensity values of the audio waveform in an array
        self.songName = None #the name of the song in question given by the user
        self.songSampleRate = None #extracted sample rate of the input MP3
        self.detectorMethod = "RNN" #default detection method
        self.startTime = 0
        self.endTime = 60


    def uploadSong(self, songName):
        self.songName = songName
        sampleRate, data = read(songName)
        if len(data.shape) == 2:
            data = data[:, 0] + data[:, 1]

        data = np.array(data, dtype=np.float32)
        self.songData = data; self.songSampleRate = sampleRate
        self.endTime = math.floor(np.size(data) / sampleRate)

    def MP3toWAV(self, src, dst):
        """MP3 to numpy array"""
        if os.path.exists(dst + ".wav"):
            os.remove(dst + ".wav")
        sound = pydub.AudioSegment.from_mp3(src)
        sound.export(dst + ".wav", format="wav")

    # simple peak detection
    def peakDetect(self, data):
        max_val = np.amax(abs(data))
        peak_ndx = np.where(data == max_val)
        if len(peak_ndx[0]) == 0:  # if nothing found then the max must be negative
            peak_ndx = np.where(data == -max_val)
        return peak_ndx

    def peakPicking(self, beat_times, total_samples, kernel_size, offset):

        # smoothing the beat function
        cut_off_norm = len(beat_times) / total_samples * 100 / 2
        b, a = signal.butter(1, cut_off_norm)
        beat_times = signal.filtfilt(b, a, beat_times)

        # creating a list of samples for the rnn beats
        beat_samples = np.linspace(0, total_samples, len(beat_times), endpoint=True, dtype=int)

        n_t_medians = signal.medfilt(beat_times, kernel_size=kernel_size)
        offset = 0.01
        peaks = []

        for i in range(len(beat_times) - 1):
            if beat_times[i] > 0:
                if beat_times[i] > beat_times[i - 1]:
                    if beat_times[i] > beat_times[i + 1]:
                        if beat_times[i] > (n_t_medians[i] + offset):
                            peaks.append(int(beat_samples[i]))
        return peaks

    def detectBPM(self, method):
        if self.songName is not None:
            bpm = None; beatPositions = None
            self.detectorMethod = method

            if self.detectorMethod == "RNN":
                bpm, beatPositions = self.detectBPM_RNN(self.songData)
            elif self.detectorMethod == "SP":
                bpm = self.detectBPM_SignalProcessing(self.songData, self.songSampleRate)
            elif self.detectorMethod == "Librosa":
                bpm = self.detectBPM_Librosa(self.songData, self.songSampleRate)
            else:
                print("Method chosen doesn't exist")
            return bpm, beatPositions
        else:
            raise ValueError('Upload song first!')


    def detectBPM_RNN(self, y):

        t1 = self.startTime * 1000  # Works in milliseconds
        t2 = self.endTime * 1000 # take the first x seconds (it takes a while after 60 seconds)
        newAudio = AudioSegment.from_wav(self.songName)
        newAudio = newAudio[t1:t2]
        newAudio.export('/tmp/test.wav', format="wav")  # Exports to a wav file in the current path.

        tPred = madmom.features.tempo.TempoEstimationProcessor(method='acf', min_bpm=40, max_bpm=200, fps=100)
        rnn_processor = RNNBeatProcessor(online="False")("/tmp/test.wav")
        proc = BeatTrackingProcessor(fps=100, tempo_estimator = tPred)
        result = tPred(rnn_processor)[0][0]
        beatTiming = proc(rnn_processor)
        """maxSize = len(beatTiming)
        i = 0
        while i < maxSize - 1:
            if (beatTiming[i + 1] - beatTiming[i]) < 60 / result * 0.75:
                beatTiming = np.delete(beatTiming, i + 1)
            elif (beatTiming[i + 1] - beatTiming[i]) > 60 / result * 1.25:
                beatTiming = np.insert(beatTiming, i + 1, (beatTiming[i + 1] + beatTiming[i]) / 2)
            maxSize = len(beatTiming)
            i += 1"""

        return result, beatTiming

    def detectBPM_Librosa(self, y, fs):
        y = y.astype('float32')
        # onset_env = librosa.onset.onset_strength(y, sr=fs)
        tempo = librosa.beat.tempo(y=y, sr=fs, max_tempo=250)
        return tempo
        pass

    def detectBPM_SignalProcessing(self, y, fs):
        cA = []
        cD = []
        correl = []
        cD_sum = []
        levels = 4
        max_decimation = 2 ** (levels - 1)
        min_ndx = math.floor(60.0 / 220 * (fs / max_decimation))
        max_ndx = math.floor(60.0 / 40 * (fs / max_decimation))

        for loop in range(0, levels):
            cD = []
            # 1) DWT
            if loop == 0:
                [cA, cD] = pywt.dwt(y, "db4")
                cD_minlen = len(cD) / max_decimation + 1
                cD_sum = np.zeros(math.floor(cD_minlen))
            else:
                [cA, cD] = pywt.dwt(cA, "db4")

            # 2) Filter
            cD = signal.lfilter([0.01], [1 - 0.99], cD)

            # 4) Subtract out the mean.

            # 5) Decimate for reconstruction later.
            cD = abs(cD[:: (2 ** (levels - loop - 1))])
            cD = cD - np.mean(cD)

            # 6) Recombine the signal before ACF
            #    Essentially, each level the detail coefs (i.e. the HPF values) are concatenated to the beginning of the array
            cD_sum = cD[0 : math.floor(cD_minlen)] + cD_sum

        if [b for b in cA if b != 0.0] == []:
            return self.no_audio_data()

        # Adding in the approximate data as well...
        cA = signal.lfilter([0.01], [1 - 0.99], cA)
        cA = abs(cA)
        cA = cA - np.mean(cA)
        cD_sum = cA[0 : math.floor(cD_minlen)] + cD_sum

        # ACF
        correl = np.correlate(cD_sum, cD_sum, "full")

        midpoint = math.floor(len(correl) / 2)
        correl_midpoint_tmp = correl[midpoint:]
        peak_ndx = self.peakDetect(correl_midpoint_tmp[min_ndx:max_ndx])
        if len(peak_ndx) > 1:
            return self.no_audio_data()

        peak_ndx_adjusted = peak_ndx[0] + min_ndx
        bpm = 60.0 / peak_ndx_adjusted * (fs / max_decimation)

        return bpm

    def plotAudioSignalWithBeatID(self, beatTimes):

        x = np.arange(0,60-self.startTime,1/self.songSampleRate)
        fig = go.Figure(data=go.Scatter(x=x, y=self.songData[self.startTime*self.songSampleRate:60*self.songSampleRate]))
        for beat in beatTimes:
            fig.add_vline(x=beat, line_width=1, line_dash="dash", line_color="green")
        fig.update_layout(
            title=self.songName,
            xaxis_title="time (seconds)",
            yaxis_title="intensity",
            font=dict(
                family="Times New Roman",
                size=18,
            )
        )
        fig.show()

    def no_audio_data(self):
        print("No audio data for sample, skipping...")
        return None, None

########################################################################################################################
#Sample usage
if __name__ == "__main__":
    startTime = time.time()
    song = "joker"
    print("Starting Beat Detection...")
    td = tempoDetector()
    td.uploadSong(song)
    bpm, beatTimes = td.detectBPM("RNN")
    endTime = time.time()
    print("Runtime: " + str(round(endTime - startTime, 2)) + "s")
    print("BPM: " + str(round(bpm)))
    #print("Plotting Beat Aligned Graph...")
    #td.plotAudioSignalWithBeatID(beatTimes)
    print("Ending Beat Detection...")

########################################################################################################################
