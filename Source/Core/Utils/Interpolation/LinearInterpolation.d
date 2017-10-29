import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.datetime, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding;

import Rescale : Rescale;


class LinearInterp
{
    this(float[][] points, float modulo)
    {
        interpPoints = points;
        this.modulo = modulo;
    }

    this(float[][] points)
    {
        auto m = points.map!(x => x[1]).reduce!max;

        this(points, m);
    }

    float interp(float x)
    {
        x = std.math.fmod(x, modulo);
        int index = findThresholdIndex(x);
        if (index == -1)
            return interpPoints[0][1];
        if (index >= interpPoints.length - 1)
            return interpPoints[$ - 1][1];

        float[2] l = [interpPoints[index][0], interpPoints[index + 1][0]];
        float[2] h = [interpPoints[index][1], interpPoints[index + 1][1]];
        auto sc = new Rescale!float(l, h);
        return sc.calc(x);
    }

    int findThresholdIndex(float x)
    {
        if (x < interpPoints[0][0])
            return -1;
        foreach (index, p; interpPoints)
        {
            if (x < p[0])
                return index - 1;
        }
        return interpPoints.length;
    }

    float[][] interpPoints;
    float modulo;
}
