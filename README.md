# zang
Audio library written in [Zig](https://ziglang.org/) 0.7.0.

This library provides functions to "paint" audio (generators and effects) into buffers. (How the buffers get sent to the audio device is out of the scope of the library, but can be seen in the provided examples.)

The library is very low-level. There are no dynamic allocations and the API is on the level of assembly programming (check out the "paint" functions in the examples). If I add higher level features, they will be in separate libraries.

## Examples
The examples (except `write_wav`) use [SDL2](https://www.libsdl.org/), so make sure that's installed.

Running the examples (again, except `write_wav`) will display a window with some information, including a waveform and FFT spectrum display. Press F1 for built-in help information.

Before building the examples, you will need to initialize git submodules, as some of the examples use an external dependency ([zig-wav](https://git.sr.ht/~dbandstra/zig-wav)).

*Note*: You may have to clear the `zig-cache` folder in between building different examples. This bug will be fixed in Zig 0.7.1.

```
git submodule init
git submodule update
```

`zig build play`: You can play a simple synthesizer with the keyboard. Home row to play a C major scale, sharps/flats in the qwerty row. Hold space to play a low C in a separate voice.

`zig build song`: Plays Bach's Toccata and Fugue in D Minor in full. The song is parsed from a text file. For now that parser is custom to this example.

`zig build subsong`: Like `play`, but a small melody is played for each note, pitched by the frequency of the key you press. The melody is encapsulated in a module, which looks on the outside like any other module (oscillators, etc).

`zig build envelope`: Hit the spacebar to trigger a note with a slow progressing ADSR envelope. This is a stripped down example making it easy to look at the shape of the envelope in the visualizer.

`zig build stereo`: A wind-like filtered noise effect slowly oscillates from side to side. (Probably too subtle to be a good stereo demonstration, you might need headphones to even notice it.)

`zig build curve`: Like `subsong`, but plays a sound defined by smooth curves instead of discrete notes.

`zig build detuned`: Like `play`, but the instrument warbles randomly. Press spacebar to cycle through a few modes and effects.

`zig build portamento`: Play a monophonic synth with portamento (gliding between notes). The instrument is composed of filtered noise, where the resonance frequency is controlled by the keyboard. (Note: you must hold down keys to get the portamento effect. When there are gaps between keypresses, the portamento is reset.)

`zig build arpeggiator`: Rapid chiptune-like arpeggiator that cycles between whatever keys you have held down.

`zig build sampler`: Loop a WAV file (drum loop from [free-loops.com](http://free-loops.com/6791-live-drums.html)). Press space to restart the loop at a randomly altered playback speed. Press 'd' to toggle a distortion effect.

`zig build polyphony`: Each key is an individual voice so you can hold down as many keys as your keyboard wiring lets you (this is a brute-force approach to polyphony - as many voices as there are keys). Press space to cycle through various levels of decimation (artificial sample rate reduction).

`zig build polyphony2`: A variant of the above, but limited to 3 voices of polyphony. Each new note takes over the stalest voice slot.

`zig build delay`: Play the keyboard with a stereo filtered echo effect.

`zig build mouse`: Play the keyboard while changing sound parameters by moving the mouse.

`zig build two`: Play an instrument controlled by two input sources (note frequency and oscillator duty cycle are controlled with separate ranges of keys on the keyboard, but both trigger the instrument's envelope). I'm not sure that this demonstrates anything actually useful.

`zig build write_wav`: Writes the melody of the `song` example to a file called "out.wav" in the current directory. It does not use SDL or libc.

In the interactive examples, you can press the backquote/tilde key to begin recording your keypresses. Press it again to stop recording and play back the recorded keypresses in a loop. Press it a third time to turn it off.

## Features
Modules:

* Curve: renders a curve (array of curve nodes) to a buffer using one of several interpolation functions
* Decimator: imitate a lower sample rate
* Distortion: overdrive/clip the input sound
* Envelope: ADSR (attack, decay, sustain, release) envelope generator
* Filter: lowpass, highpass, notch, bandpass, including resonance
* Gate: a simpler Envelope, just outputs 1 or 0 based on note on and off events
* Noise: basic white noise
* Portamento: interpolate incoming stream of values (e.g. note frequencies)
* PulseOsc: square wave oscillator
* Sampler: play an audio file (wav loader provided), resampling according to the note frequencies
* SineOsc: sine wave oscillator
* TriSawOsc: triangle/sawtooth oscillator

## Goals
My goals for the core library:

* Small set of standard generators and filters
* Decent audio quality (deal with oscillator aliasing, wav resampling...)
* Total modularity (single-purpose modules with controllable inputs)
* Ability to play music
* Ability to provide sound effects for a game
* Clean (as possible), idiomatic Zig API
* Lean inner loops
* Overall small and simple codebase
* Documentation

## Zangscript
This is WIP. It's a DSL that can be compiled into Zig code. Writing Zangscript will be a lot terser and more expressive than writing Zig code by hand using the zang API. It's totally optional, the core zang library has no dependency on it. I'll document it more when I make more progress. You can try it out by running:

```
zig build zangc
zig-cache/zangc -o examples/scriptgen.zig examples/script.txt
zig build script
```

The scripts can also be evaluated at runtime. The result should be the same as when compiling to Zig, but you trade efficiency for the ability to reload changes to the script on the fly.

```
# loads and runs examples/script.txt
zig build script_runtime_mono  # monophonic, or
zig build script_runtime_poly  # polyphonic
```

If you set the `ZANG_LISTEN_PORT` environment variable, the zang example program will open a UDP socket. Send the string `reload` to this port and the example will reload (same as pressing Enter). You can hook this up to a filesystem-watching tool to get reload-on-save (see the included script `watch_script.sh` which uses `inotifywait`).

```
ZANG_LISTEN_PORT=8888 zang build script_runtime

# then, in another terminal (bash only):
echo -n reload > /dev/udp/localhost/8888
```
