module Core.Utils.Log;

import std.stdio;

struct Log
{
static:
    void write(T...)(T output)
    {
        string indent = "";
        foreach (_; 0 .. indentLevel)
            indent ~= "  ";
        output[0] = indent ~ output[0];
        writefln(output);
    }

    auto writeIndent(T...)(T output)
    {
        write(output);
        return scoped!ScopedIndent();
    }

private:
    class ScopedIndent
    {
        this()
        {
            indentLevel++;
        }

        ~this()
        {
            indentLevel--;
        }
    }

    int indentLevel = 0;
}

string LogWrite(T)(T args, int lineNumber = __LINE__)
{
    return "debug auto ___" ~ to!string(lineNumber) ~ " = Log.writeIndent(\"" ~ args ~ "\"); \n ";
}
