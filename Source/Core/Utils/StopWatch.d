module Core.Utils.StopWatch;

import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.datetime, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding;


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