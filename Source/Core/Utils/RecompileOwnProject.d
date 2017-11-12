module Core.RecompileOwnProject;

import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.datetime, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding;

import DirWatch;


class RecompileOwnProject
{
    this()
    {
        dw = new DirWatch();
        dw.registerMethod((string fileName) {
            auto restartCommand = "
					taskkill /im " ~ thisExePath.baseName
                ~ " /F
					cls
					dub build --nodeps
					bin\\" ~ thisExePath.baseName;
            auto batFile = "res.bat";
            std.file.write(batFile, restartCommand.detab);
            system(batFile.ptr);
        }, __FILE__);
    }

    public void checkChanges()
    {
		while(true)
        dw.handleChanges();
    }

    private DirWatch dw;
}