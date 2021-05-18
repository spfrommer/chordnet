'use strict';

const fs = require('fs');
const toWav = require('audiobuffer-to-wav');
const arrayBufferToAudioBuffer = require('arraybuffer-to-audiobuffer')
const createBuffer = require('audio-buffer-from')

const AudioContext = require('web-audio-api').AudioContext;
const audioContext = new AudioContext;

const WebSocketServer = require('ws').Server
const wss = new WebSocketServer({ port: 8081 });

function toArrayBuffer(buf) {
    var ab = new ArrayBuffer(buf.length);
    var view = new Uint8Array(ab);
    for (var i = 0; i < buf.length; ++i) {
        view[i] = buf[i];
    }
    return ab;
}

fs.promises.rmdir('../data', { recursive: true }).then(
    () => fs.mkdirSync('../data')
);

wss.on('connection', ((ws) => {
    var count = 0;
    ws.on('message', (message) => {
        if (count % 2 == 0) {
            var buffer = toArrayBuffer(message);
            buffer = new Float32Array(buffer);
            var audioBuffer = createBuffer(buffer);

            var audioStack = [];

            var header = require('waveheader');

            let wav = toWav(audioBuffer); 
            var chunk = new Uint8Array(wav);
            fs.appendFile('bb.wav', new Buffer(chunk), function (err) {});
        } else {
            console.log('Renaming to: ' + message);
            var target = '../data/' + message + '.wav'
            fs.rename('./bb.wav', target, function(e) {
                if (e) console.log(e);
            })
        }
        count += 1;
    });

    ws.on('end', () => {
        console.log('Connection ended...');
    });

    ws.send('Hello Client');
}));
