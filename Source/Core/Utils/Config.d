module Core.Utils.Config;

import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding,
    std.complex;
	
import Core.Utils.StopWatch;

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
            refreshJson();

        return json[valueName].asString.to!T;
    }
}