module Core.Utils.RandomGenerator;

import std.random;

struct RandomGenerator
{
	static Random generator = Random(1);

	static auto opCall(T)(T array)
	{
		return array[uniform(0, array.length, generator)];
	}
	static auto opCall(T)(T from, T to)
	{
		return uniform(from, to, generator);
	}
	static bool chance(float odds)
	{
		return uniform(0., 1., generator) < odds;
	}
}
