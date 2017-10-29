import core.simd, core.stdc.stdlib, core.runtime, core.thread, std.algorithm,
    std.array, std.conv, std.datetime, std.file, std.format, std.functional,
    std.json, std.math, std.meta, std.numeric, std.parallelism, std.path,
    std.process, std.random, std.range, std.signals, std.stdio, std.string,
    std.traits, std.typecons, std.typetuple, std.variant, std.encoding;

import derelict.openal.al;

import libasync;
import libasync.watcher;
import libasync.threads;


class DirWatch
{
    this()
    {
        eventLoop = getThreadEventLoop();

        DWChangeInfo[] changes = new DWChangeInfo[8];

        watcher = new AsyncDirectoryWatcher(eventLoop);
        watcher.run({
            while (watcher.readChanges(changes) > 0)
            {
                foreach (change; changes)
                    onDirectoryEvent(change);
            }
        });
    }

    auto handleChanges()
    {
        return eventLoop.loop();
    }

    void registerMethod(void delegate(string) func, string filePath)
    {
        watcher.watchDir(filePath.dirName);
        funcs[filePath] = func;
    }

    void onDirectoryEvent(DWChangeInfo change)
    {
        if (!change.path.empty)
        {
            change.path.writeln;
            if (change.path in funcs)
                funcs[change.path](change.path);
        }
    }

    AsyncDirectoryWatcher watcher;
    EventLoop eventLoop;
    void delegate(string)[string] funcs;
}
