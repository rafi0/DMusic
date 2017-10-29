

struct Rescale(T)
{
    this(T[2] from, T[2] to)
    {
        low = from;
        high = to;
    }

    T calc(T x)
    {
        auto ratio = (x - low[0]) / (low[1] - low[0]);
        return high[0] * (1.0f - ratio) + high[1] * ratio;
    }

    T[2] low;
    T[2] high;
}