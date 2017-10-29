module Guitar.Tone;

import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.datetime, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding;

import libasync;
import libasync.watcher;
import libasync.threads;

import derelict.openal.al;

import waved;

import LinearInterpolation;

public:

alias SoundTypeUsed = ALshort;
//alias SoundTypeUsed = ALfloat;

struct ToneData
{
    float[][][] freq;
    float seconds;
    const int sample_rate = 44100;
    int buf_size;
}

class SoundPlayer
{
	this(SoundTypeUsed[] samplesSoundType = [])
	{
		alGenSources(1, &srcId);
		//updateBuffer(samplesSoundType);
		handleErr();
		alSourcei(srcId, AL_LOOPING, buf);
	}

	void updateBuffer(SoundTypeUsed[] samplesSoundType)
	{
		alBufferData(buf, AL_FORMAT_MONO16, samplesSoundType.ptr, samplesSoundType.length, 44100);
	}

	void play()
	{
		alSourcei(srcId, AL_LOOPING, 1);
		alSourcePlay(srcId);
	}
	void stop()
	{
		alSourceStop(srcId);
		alSourcei(srcId, AL_LOOPING, 0);
	}
	ALuint buf;
	ALuint srcId;
}

auto convertDataArray(From, To)(From[] from)
{
	auto minmax = from.reduce!(min, max);
	auto extreme = max(
		std.math.abs(minmax[0]),
		std.math.abs(minmax[1]));
	if (extreme == 0)
		extreme = 1;
	return from.map!(val => 
		((val / extreme).to!float).to!To).array; 
}

ALuint createSoundWave(ToneData nd)
{
	ALuint buf;
	//writeln("alGenBuffers(1, &buf);");
	alGenBuffers(1, &buf);
	handleErr();

	//nd.seconds = nd.freq[0].map!(x => x[0]).reduce!max;
	//writefln("seconds: %s", nd.seconds);

	nd.buf_size = (nd.seconds * nd.sample_rate).to!int;

	auto linterps = nd.freq
		.map!(freqs => new LinearInterp(freqs))
		.array;
	
	float[] samplesFloat;
	samplesFloat.length = nd.buf_size;

	//writefln("frequency: %s, samples: %s", frequency, samples.length);
	auto volume = 1.;
	const scaleToShortMax = 2.pow(15) - 1;

	foreach (int n, ref sample; samplesFloat)
	{
		double x = n.to!double / nd.sample_rate;

		double waveValue = 1;
		foreach (l ; linterps)
		{
			waveValue *= sin(l.interp(x) * x * 2. * PI);
			waveValue += sin(l.interp(x) * 2. * x * 2. * PI) * 0.7;// harmonics
			waveValue += sin(l.interp(x) * 3. * x * 2. * PI) * 0.3;
			waveValue += sin(l.interp(x) * 4. * x * 2. * PI) * 0.15;
		}

		sample = volume
			* waveValue
			* scaleToShortMax - 1;
	}

	//overdriveSamples(samplesFloat);
	//distortSamples(samplesFloat);
	
	auto samplesSoundType = samplesFloat.convertDataArray!(float, SoundTypeUsed);

	//alBufferData(buf, AL_FORMAT_STEREO16, samples.ptr, nd.buf_size, nd.sample_rate);
	//alBufferData(buf, AL_FORMAT_MONO16, samples.ptr, samples.length, (samples.length / nd.seconds).to!int);
	alBufferData(buf, AL_FORMAT_MONO16, samplesSoundType.ptr, samplesSoundType.length, (samplesSoundType.length / nd.seconds).to!int);
	//alBufferData(buf, AL_FORMAT_MONO_FLOAT32, samples.ptr, samples.length, (samples.length / nd.seconds).to!int);

	auto s = Sound(nd.sample_rate, 2, samplesFloat);
	string fileName = "_%s.wav".format(nd.freq);
	s.encodeWAV(fileName);
	
	handleErr();

	ALuint srcId;
	alGenSources(1, &srcId);
	alSourcei(srcId, AL_BUFFER, buf);
	return srcId;
}

ALuint createToneData(float[] frequencies)
{
    ToneData nd;

	foreach (frequency; frequencies)
	{
		nd.freq ~= [
			[1., frequency],
			];
	}
    nd.seconds = 3.;
 
    return createSoundWave(nd);
}

void handleErr()
{
    if (ALCenum error = alGetError() != AL_NO_ERROR)
		throw new Exception(format("err: %s", error));
}

alias toneSource = memoize!createToneData;

void playSound(ALuint[] srcIds, Duration duration)
{
	foreach(srcId; srcIds)
	{
		alSourcei(srcId, AL_LOOPING, 1);
		alSourcePlay(srcId);
	}
	Thread.sleep(duration);
	foreach(srcId; srcIds)
	{
		alSourceStop(srcId);
		alSourcei(srcId, AL_LOOPING, 0);
	}
}

auto rotateArray(T)(T array, int rotation)
{
	return array[rotation..$] ~ array[0..rotation];
}

auto getMusicTones()
{
	char[] alphabet = iota(7).map!(x => (x + 'a'.to!int).to!char).array;
	
	string[] tones;

	foreach (alp; alphabet.rotateArray(2))
	{
		auto alpStr = alp.to!string;
		tones ~= alpStr;

		if (alp != 'b' && alp != 'e')
			tones ~= alpStr ~ "#";
	}

	return tones;
}

auto getIndexOfTone(string tone)
{
	if (tone.isPause)
		throw new Exception("");
	return getMusicTones
        .countUntil(tone);
}

bool isPause(string tone)
{
	return tone == "-";
}

class Tone
{
    this(string tone, int octave = 0)
    {
        this.tone = tone;
        this.octave = octave;
    }

    Tone getRelativeTone(int steps) const
    {
		if (tone.isPause)
			throw new Exception("");

		string relativeTone = getMusicTones.cycle[tone.getIndexOfTone + steps];
		int octaveChanges = (tone.getIndexOfTone + steps) / 12;

        return new Tone(relativeTone, octave + octaveChanges);
    }

    int getIndexValue() const
    {
        return tone.getIndexOfTone + octave * 12;	
    }

    float getFrequency() const
    {
		if (tone.isPause)
			return 0;
        enum twelwethRootOfTwo = 1.059463094359;
		//enum ANoteFrequency = 261.63;
		enum firstOctaveANoteFrequency = 65.406;
		return firstOctaveANoteFrequency * pow(twelwethRootOfTwo, getIndexValue);
    }

    bool isSharp()
    {
        return tone.length == 2;
    }

	string getToneIf(bool delegate (Tone) predicate)
	{
		if (predicate(this))
			return tone;
		return tone.length == 1 ? " " : "  ";
	}

    const string tone;
    const int octave;
}