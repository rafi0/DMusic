import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.datetime, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding;

import libasync;
import libasync.watcher;
import libasync.threads;

import derelict.openal.al;

import Core.Utils.RandomGenerator;
import Guitar.Tone;

ALCdevice* dev;
ALCcontext* ctx;

void initAl()
{
    DerelictAL.load();

    const defname = alcGetString(null, ALC_DEFAULT_DEVICE_SPECIFIER);
    //writefln("Default device: %s", defname);

    dev = alcOpenDevice(defname);
    ALCcontext* ctx = alcCreateContext(dev, null);

    alcMakeContextCurrent(ctx);
}

void exit_al()
{
    ctx = alcGetCurrentContext();
    dev = alcGetContextsDevice(ctx);

    alcMakeContextCurrent(null);
    alcDestroyContext(ctx);
    alcCloseDevice(dev);
}

shared static ~this()
{
    exit_al();
    destroyAsyncThreads();
}

Tone muteTone()
{
    return new Tone("X");
}

enum GuitarTuning
{
    Standard,
    Drop,
    OpenChord,
}

enum MusicalScale
{
    Pentatonic,
    Blues,
    Gama,
    Major,
}

enum Chord
{
    SingleTone,
    MinorSeventh,
    MajorSeventh,
    PowerChord,
    PowerChord5,
    PowerChord5Dyad,
    PowerChord8,
    MinorTriad,
    MajorTriad,
    AugmentedTriad,
    DiminishedTriad,
    MinorMajorSeventh,
    AugmentedMinorSeventh,
    AugmentedMajorSeventh,
    HalfDiminishedSeventh,
    DiminishedSeventh,
    SeventhFlatFive,
}

enum Note
{
    Full = 1.,
    Half = 0.5,
    Quarter = 0.25,
    Eight = 0.125,
    Sixteenth = 0.0625
}

enum PlayStyle
{
    Default,
    PalmMute,
    Staccato,
    Legato,
    PinchHarmonic,
}

auto getOneOf(T)()
{
    return [EnumMembers!T][RandomGenerator(0, EnumMembers!T.length)];
}

T stringToEnum(T)(string value)
{
    foreach (enumValue; [EnumMembers!T])
    {
        if (enumValue.to!string == value)
            return enumValue;
    }
    assert(false);
}

class TimeSignature
{
    this(){}
    this(int beats, int barLength)
    {
        this.beats = beats;
        this.barLength = barLength;
    }

    int beats;
    int barLength;
}

Tone[] getGuitarStringStartingOnTone(string tone, int octave = 0)
{
    Tone[] eString;
    eString ~= new Tone("e");
    foreach (_; 0 .. 100)
        eString ~= eString[$ - 1].getRelativeTone(1);

    Tone[] guitarString;
    guitarString ~= eString.find!(a => a.tone == tone && a.octave == octave)[0];
    foreach (_; 0 .. 24)
        guitarString ~= guitarString[$ - 1].getRelativeTone(1);

    return guitarString;
}

Tone[][] getFretboardInTuning(string rootTone, GuitarTuning tuning = GuitarTuning.Standard)
{
    Tone[][] fretboard;

    const root = new Tone(rootTone);

    if (tuning == GuitarTuning.Standard)
    {
        fretboard ~= getGuitarStringStartingOnTone(rootTone);

        fretboard ~= getGuitarStringStartingOnTone(fretboard[$ - 1][0].getRelativeTone(5).tone);
        fretboard ~= getGuitarStringStartingOnTone(fretboard[$ - 1][0].getRelativeTone(5).tone, 1);
        fretboard ~= getGuitarStringStartingOnTone(fretboard[$ - 1][0].getRelativeTone(5).tone, 1);

        fretboard ~= getGuitarStringStartingOnTone(root.getRelativeTone(7).tone, 1);
        fretboard ~= getGuitarStringStartingOnTone(rootTone, 2);
    }

    return fretboard;
}

int toneDistanceUpward(string aTone, string bTone)
{
    int aToneIndex = aTone.getIndexOfTone.to!int;
    int bToneIndex = bTone.getIndexOfTone.to!int;

    while (aToneIndex > bToneIndex)
        bToneIndex += 12;

    auto diff = bToneIndex - aToneIndex;
    if (diff < 0)
        diff += 12;
    return diff;
}

int toneDistanceClosest(string aTone, string bTone)
{
    return min(
        toneDistanceUpward(aTone, bTone), 
        toneDistanceUpward(bTone, aTone));
}

enum int[][MusicalScale] scaleDistances = [
    MusicalScale.Pentatonic : [0, 3, 5, 7, 10,],
    MusicalScale.Major : [0, 2, 3, 5, 7, 8, 10,],
    MusicalScale.Gama : [0, 2, 4, 5, 7, 9, 11],
    ];

enum int[][Chord] chordDistances = [
    Chord.SingleTone : [0],
    Chord.PowerChord : [0, 7],
    Chord.PowerChord5Dyad : [0, 5],
    Chord.PowerChord5 : [0, 5, 12],
    Chord.PowerChord8 : [0, 7, 12],
    Chord.MinorSeventh : [0, 4, 7, 10],
    Chord.MajorSeventh : [0, 4, 7, 11],
    Chord.MinorMajorSeventh : [0, 3, 7, 11],
    Chord.AugmentedMinorSeventh : [0, 4, 8, 10],
    Chord.AugmentedMajorSeventh : [0, 4, 8, 11],
    Chord.HalfDiminishedSeventh : [0, 3, 6, 11],
    Chord.DiminishedSeventh : [0, 3, 6, 9],
    Chord.SeventhFlatFive : [0, 4, 6, 10],
    Chord.MinorTriad : [0, 4, 7],
    Chord.MajorTriad : [0, 3, 7],
    Chord.AugmentedTriad : [0, 4, 8],
    Chord.DiminishedTriad : [0, 3, 6],
    ];

bool toneIsInScale(string tone, string rootTone, MusicalScale scale)
{
    return scaleDistances[scale].canFind(toneDistanceUpward(rootTone, tone));
}

Tone[] getScaleTones(string rootTone, MusicalScale scale)
{
    Tone[] result;

    Tone root = new Tone(rootTone);
    
    foreach(distance; scaleDistances[scale])
        result ~= root.getRelativeTone(distance);

    return result;
}

bool toneisPartOfChord(Tone tone, string rootTone, Chord chord)
{
    return tone.toneAmong(getChordTones(new Tone(rootTone), chord));
}

Tone[] getChordTones(const Tone rootTone, Chord chord)
{
    Tone[] result;
    
    foreach(distance; chordDistances[chord])
        result ~= rootTone.getRelativeTone(distance);

    return result;
}

void playTones(Tone[] tones, Duration duration)
{
    ALuint[] soundIds;
    soundIds ~= toneSource(tones.map!(t => t.getFrequency).array);
    playSound(soundIds, duration);
}

class FretboardState
{
    this(Tone[][] fretboard, DoForTone doIfToneIsPlayed, DoForTone doIfToneIsNotPlayed, DoForEachString doForEachString)
    {
        this.fretboard = fretboard;
        this.doIfToneIsPlayed = doIfToneIsPlayed;
        this.doIfToneIsNotPlayed = doIfToneIsNotPlayed;
        this.doForEachString = doForEachString;
    }

    void setPlayedTones(Tone[] tones)
    {
        foreach(int x, str; fretboard)
        {
            foreach(int y, tone; str)
            {
                if (tone.toneIndexAmong(tones))
                    doIfToneIsPlayed(tone, x, y);
                else
                    doIfToneIsNotPlayed(tone, x, y);
            }
            doForEachString(str);
        }
    }
private:
    alias DoForTone = void function(const Tone, int x, int y);
    alias DoForEachString = void function(const Tone[]);
    DoForTone doIfToneIsPlayed;
    DoForTone doIfToneIsNotPlayed;
    DoForEachString doForEachString;
    Tone[][] fretboard;
}

bool toneIndexAmong(Tone tone, Tone[] tones)
{
    return tones.canFind!(n => n.getIndexValue == tone.getIndexValue);
}

bool toneAmong(Tone tone, Tone[] tones)
{
    return tones.canFind!(n => n.tone == tone.tone);
}

class Sound
{
    this(Tone tone, Note note, Chord chord)
    {
        this.tone = tone;
        this.note = note;
        this.chord = chord;
    }
    Tone tone;
    Note note;
    Chord chord;
}

struct TWithWeight(T)
{
    T value;
    float weight;
}

bool between(float value, float lower, float higher)
{
    return value >= lower && value < higher;
}

auto chooseAmong(T)(T collection)
{
    auto weightSum = collection.map!(el => el.weight)
        .sum;

    auto hit = RandomGenerator(0., weightSum);

    float accumulatedWeight = 0;
    foreach(el; collection)
    {
        if (hit.between(accumulatedWeight, accumulatedWeight+el.weight))
            return el.value;
        accumulatedWeight += el.weight;
    }
    assert(false);
}

class GuitarTrack
{
    Sound[] createBar()
    {
        Sound[] result;

        float barFill = 0;

        //choose chord
        //choose tone from chord
        // root tone on accent?

        auto scaleTones = scaleRoot.getScaleTones(scale);

        while (barFill < timeSignature.barLength)
        {
            Note note;
            do
            {
                note = getOneOf!Note;
            }while (barFill + note > timeSignature.barLength);

            Tone tone = RandomGenerator.chance(0.15)
                ? muteTone
                : RandomGenerator(scaleTones);

            //Chord chord = chordDistances.keys[RandomGenerator(0, chordDistances.length)];
            Chord chord = Chord.PowerChord;

            result ~= new Sound(tone, note, chord);

            barFill += note;
        }

        //result[$-1].note -= (barFill - timeSignature.barLength);

        assert(result.map!(n => n.note).sum == timeSignature.barLength);

        return result;
    }

    enum BarCreationMode
    {
        Weights,
        Cyclic,
    }
    Sound[] createBar2(BarCreationMode mode)(
        TWithWeight!Note[] nwws,
         TWithWeight!Tone[] twws,
         TWithWeight!Chord[] cwws)
    {
        Sound[] result;

        float barFill = 0;

        auto scaleTones = scaleRoot.getScaleTones(scale);

        while (barFill < timeSignature.barLength)
        {
            static if (mode == BarCreationMode.Weights)
            {
                Note note = chooseAmong(nwws);
                Tone tone = chooseAmong(twws);
                Chord chord = chooseAmong(cwws);
            }

            result ~= new Sound(tone, note, chord);

            barFill += note;
        }

        result[$-1].note -= (barFill - timeSignature.barLength);
        assert(result.map!(n => n.note).sum == timeSignature.barLength);

        return result;
    }

    string soundsToString()
    {
        return currentSounds.map!
            (sound => format("%s %s %s\n", sound.tone.tone, sound.chord, sound.note))
            .join;
    }

    string soundsToString2()
    {
        string result;
        foreach (sound; currentSounds)
        {
            int sixteenthCount = (sound.note / Note.Sixteenth).to!double.to!int;
            char[] spaces = new char[sixteenthCount];
            spaces[] = '-';
            result ~= sound.tone.tone ~ spaces;
        }
        return result;
    }

    void playCurrentSounds()
    {
        float bps = bpm / 60.;
        float fullNoteDuration = 1. / bps;

        foreach (sound; currentSounds)
        {
            auto noteDuration = dur!"msecs"(
                (fullNoteDuration * sound.note * 1000.
                   ).to!int);
            if (sound.tone.tone == muteTone.tone)
	            Thread.sleep(noteDuration);
	        else
	        {
                sound.tone
                    .getChordTones(sound.chord)
                    .playTones(noteDuration);
            }
        }
    }

    string serializeData()
    {
        string result;
        result ~= format("%s %s %s %s %s\n", timeSignature.beats, timeSignature.barLength, scaleRoot, bpm, scale);

        foreach (sound; currentSounds)
        {
            result ~= format("%s %s %s\n", sound.note, sound.tone.tone, sound.chord);
        }

        return result;
    }

    void deserializeData(string data)
    {
        currentSounds = [];
        auto lines = data.split("\n");
        auto header = lines[0].split;

        timeSignature = new TimeSignature();
        timeSignature.beats = header[0].to!int;
        timeSignature.barLength = header[1].to!int;

        scaleRoot = header[2];
        bpm = header[3].to!int;
        scale = header[4].stringToEnum!MusicalScale;

        foreach (line; lines[1..$])
        {
            auto values = line.split;

            if (values.length < 3)
                continue;

            auto note = values[0].stringToEnum!Note;
            auto tone = new Tone(values[1]);
            auto chord = values[2].to!Chord;

            currentSounds ~= new Sound(tone, note, chord);
        }
    }

    Sound[] currentSounds;

    int bpm;
    MusicalScale scale;
    string scaleRoot;
    TimeSignature timeSignature;
}

class StopWatch
{
    Duration refreshInterval;
    SysTime lastTime;

    this(Duration refreshInterval = dur!"msecs"(1000))
    {
        this.refreshInterval = refreshInterval;
        lastTime = Clock.currTime();
    }

    bool timePassed()
    {
        auto currentTime = Clock.currTime();
        if (lastTime + refreshInterval < currentTime)
        {
            lastTime = currentTime;
            return true;
        }
        return false;
    }
}

string asString(JSONValue v) 
{
    if(v.type == JSON_TYPE.FLOAT)
        return v.floating.to!string;
    else if(v.type == JSON_TYPE.INTEGER)
        return v.integer.to!string;
    else if(v.type == JSON_TYPE.UINTEGER) 
        return v.uinteger.to!string;
    else if(v.type == JSON_TYPE.TRUE)
        return "true";
    else if(v.type == JSON_TYPE.FALSE)
        return "false";
    else if(v.type == JSON_TYPE.ARRAY)
        return v.array.to!string;
    throw new Exception("unexpected type: " ~ to!string(v.type));
}

class Config
{
    JSONValue json;
    StopWatch stopWatch;
    static Config singleton;
    string fileName = "config.cfg";

    this()
    {
        stopWatch = new StopWatch();
        if (!fileName.exists)
            std.file.write(fileName, "{}");
        refreshJson();
    }

    void refreshJson()
    {
        //"refreshing config".writeln;
        string fileContent = fileName.readText;
        json = fileContent.parseJSON;
    }

    static T getValue(T)(string valueName)
    {
        if (singleton is null)
            singleton = new Config();
        return singleton.getValueImpl!T(valueName);
    }

    T getValueImpl(T)(string valueName)
    {
        if (valueName !in json)
        {   
            json.object[valueName] = JSONValue(T.init);
            std.file.write(fileName, json.toPrettyString);
        }

        if (stopWatch.timePassed)
            return json[valueName].asString.to!T;

        refreshJson();

        return json[valueName].asString.to!T;
    }
}

void recordAndPlayInput()
{
    ALuint source;
    ALuint[3] buffers;
    SoundTypeUsed[5000] samples;
    ALuint buf;
    ALint val;
    const sample_rate = 44100;

    alGenSources(1, &source);
    alGenBuffers(3, buffers.ptr);

    alBufferData(buffers[0], AL_FORMAT_MONO16, samples.ptr, samples.length.to!int, sample_rate);
    alBufferData(buffers[1], AL_FORMAT_MONO16, samples.ptr, samples.length.to!int, sample_rate);
    alBufferData(buffers[2], AL_FORMAT_MONO16, samples.ptr, samples.length.to!int, sample_rate);
    alSourceQueueBuffers(source, 3, buffers.ptr);

    alDistanceModel(AL_NONE);

    StopWatch sw = new StopWatch(dur!"msecs"(300));

    dev = alcCaptureOpenDevice(null, sample_rate, AL_FORMAT_MONO16, samples.length/2);

    alcCaptureStart(dev);
    alSourcePlay(source);

    while (Config.getValue!bool("keepRunning"))
    {
        alGetSourcei(source, AL_BUFFERS_PROCESSED, &val);
        if(val <= 0)
            continue;

        alcGetIntegerv(dev, ALC_CAPTURE_SAMPLES, 1, &val);

        alcCaptureSamples(dev, samples.ptr, val);

        if (sw.timePassed)
            samples.array.stride(500).writeln;

        // TODO FFT here

        void distortSamples(T)(ref T[] samples)
        {
            foreach (ref s; samples)
            {
                if (s > 100)
                    s  *= 3;
            }
        }

        alSourceUnqueueBuffers(source, 1, &buf);
        alBufferData(buf, AL_FORMAT_MONO16, samples.ptr, val*2, sample_rate);
        alSourceQueueBuffers(source, 1, &buf);

        alGetSourcei(source, AL_SOURCE_STATE, &val);

        if(val != AL_PLAYING)
            alSourcePlay(source);
    }

    alcCaptureStop(dev);
    alcCaptureCloseDevice(dev);

    alSourceStop(source);
    alDeleteSources(1, &source);
    alDeleteBuffers(3, buffers.ptr);
    alDeleteBuffers(1, &buf);
}

void main()
{
    initAl();

    recordAndPlayInput();

    //"d".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(550));
    
    auto fbs = new FretboardState(
        getFretboardInTuning("e"),
        (tone, x, y) => write("|" ~ (tone.tone.length == 1 ? tone.tone ~ " " : tone.tone)),
        (tone, x, y) => write("|  "),
        (tones) => writeln
    );
    
    //fbs.setPlayedTones("e".getChordTones(Chord.PowerChord));

    //TODO fix
    auto toneToTabLine(Tone[] tones, string guitarTuning = "e")
    {
        string[] result;

        auto fretboard = getFretboardInTuning(guitarTuning);

        string getFretIndex(Tone tone, int startStringIndex)
        {
            auto guitarString = fretboard[startStringIndex];
            auto maxFretIndex = min(12, guitarString.length);

            foreach(i, stringTone; guitarString[0..maxFretIndex])
            {
                //"%s vs %s".format(tone.getIndexValue, stringTone.getIndexValue).writeln;
                if (tone.getIndexValue == stringTone.getIndexValue)
                {
                    format("%s %s", i, tone.tone).writeln;
                    return i.to!string;
                }
            }
            return "-";
        }
        foreach (index; 0..6)
        {
            string fretIndex;
            //foreach (tone; tones)//FUBAR
            fretIndex = getFretIndex(tones[0], index);
            result ~= fretIndex;
        }

        return result;
    }

    auto tonesToTab(Tone[][] tones)
    {
        string[][] tabLines;

        foreach(tone; tones)
            tabLines ~= toneToTabLine(tone);

        string result;

        foreach_reverse(stringIndex; 0..6)
        {
            foreach(i; 0..tabLines.length)
                result ~= tabLines[i][stringIndex];
            result ~= "\n";
        }

        return result;
    }

    Tone[] tabLineToToneChord(string tabLine)
    {
        auto fretboard = getFretboardInTuning("e");
        auto fretIndexes = tabLine.split();

        Tone[] result;
        foreach_reverse(stringIndex, fretIndex; fretIndexes)
        {
            if (fretIndex != "-")
                result ~= fretboard[5-stringIndex][fretIndex.to!int];
        }
        return result;
    }

    Tone[][] tabLineToSong(string tab)
    {
        Tone[][] result;

        auto strings = tab.split();

        auto stringTabs = strings.map!(str => str.split());

        const tabLength = stringTabs[0].length;
        foreach(index; 0..tabLength)
        {
            string singleTab;
            foreach(stringTab; stringTabs)
                singleTab ~= stringTab[index] ~ "\n";
            result ~= tabLineToToneChord(singleTab);
        }

        return result;
    }

    version(none)
    tabLineToSong("-\n-\n-\n2\n2\n0")[0]
        .map!(x => x.tone)
        .writeln;

    version(none)
    tonesToTab([getChordTones("d", Chord.PowerChord).map!(n => n.getRelativeTone(12)).array])
        .writeln;// TODO naprawic
    //toneToTabLine(getChordTones("e", Chord.PowerChord)).writeln;

    GuitarTrack gt = new GuitarTrack();

    gt.timeSignature = new TimeSignature(4, 4);
    gt.scale = MusicalScale.Pentatonic;
    gt.scaleRoot = "e";
    gt.bpm = 90;

    if (!exists("music"))
        mkdir("music");

    void func()
    {
        gt.currentSounds = gt.createBar2!(GuitarTrack.BarCreationMode.Weights)([
            TWithWeight!Note(Note.Quarter, 10),
            //TWithWeight!Note(Note.Eight, 1),
            ],[
            TWithWeight!Tone(new Tone("e"), 4),
            //TWithWeight!Tone(new Tone("f"), 1),
            TWithWeight!Tone(muteTone, 2),
            ],[
                TWithWeight!Chord(Chord.PowerChord, 1),
                TWithWeight!Chord(Chord.PowerChord5, 1),
                TWithWeight!Chord(Chord.PowerChord5Dyad, 1),
            ]
        );

        auto currentTime = std.datetime.systime.Clock.currTime();

        std.file.write(format("music/music_%s_%s_%s_%s_%s.txt", currentTime.month, currentTime.day, currentTime.hour, currentTime.minute, currentTime.second), gt.serializeData());
        gt.serializeData().writeln;
        gt.deserializeData(gt.serializeData());
        gt.playCurrentSounds();
    }

    //gt.deserializeData(readText("music/music_oct_3_23_23_46.txt"));
    //gt.playCurrentSounds();

    //func;

    //auto toneCycle = "c".getScaleTones(MusicalScale.Pentatonic).cycle;
    //iota(10).each!(i => [toneCycle[RandomGenerator(0, 10)]].playTones(dur!"msecs"(RandomGenerator(1, 5) * 250)));

    version (none)
    getFretboardInTuning("e").each!((str) {
        str.map!(n => n.tone.toneIsInScale("e", MusicalScale.Major)
            ? n.tone 
            : n.tone.length == 1 
                ? " "
                : "  ").writeln;
        writeln;
    });

    version (none)
    getFretboardInTuning("e")
        .each!((str) {
            str.each!((n){
                if (n.tone.toneIsInScale("e", MusicalScale.Pentatonic))
                {
                    playSound([
                        toneSource([n.getFrequency]),
                    ], dur!"msecs"(150));
                }
            });
        })
    ;

    version (none)
        getFretboardInTuning("e").each!((str) {
            str.map!(n => n.getToneIf((Tone n) {
                    return toneisPartOfChord(n, "e", Chord.MinorSeventh);
                })).writeln;
            writeln;
        });

    assert(toneDistanceUpward("e", "e") == 0);
    assert(toneDistanceUpward("e", "f") == 1);
    assert(toneDistanceUpward("f", "e") == 11);
    assert(toneDistanceUpward("e", "a") == 5);
    assert(toneDistanceUpward("c", "b") == 11);
    assert(toneDistanceClosest("c", "b") == 1);
    assert(toneDistanceClosest("a", "d") == 5);

    version (none)
    {
        "d".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "f".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "g".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(1200));

        "d".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "f".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "g#".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(300));
        "g".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(900));

        "d".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "f".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "g".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(1200));
        "f".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(600));
        "d".getChordTones(Chord.PowerChord).playTones(dur!"msecs"(1500));
    }
}

unittest
{
    assert(toneDistanceUpward("e", "e") == 0);
    assert(toneDistanceUpward("e", "f") == 1);
    assert(toneDistanceUpward("f", "e") == 11);
    assert(toneDistanceUpward("e", "a") == 5);
    assert(toneDistanceUpward("c", "b") == 11);
    assert(toneDistanceClosest("c", "b") == 1);
    assert(toneDistanceClosest("a", "d") == 5);

    GuitarTrack gt = new GuitarTrack();
    gt.timeSignature = new TimeSignature(4, 4);
    gt.scale = MusicalScale.Pentatonic;
    gt.scaleRoot = "e";
    gt.bpm = 60;
    gt.currentSounds = gt.createBar();
    auto before = gt.soundsToString2;
    auto firstSerialization = gt.serializeData();
    gt.deserializeData(gt.serializeData());
    auto after = gt.soundsToString2;
    auto secondSerialization = gt.serializeData();
    assert(before == after);
    assert(firstSerialization == secondSerialization);
}