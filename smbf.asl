state("SuperMeatBoyForever", "6201.1266.1561.138 (EGS)") {
    // as a number of frames (at 60 fps), the speedrun timer that is displayed in the upper right
    uint frameCount : "SuperMeatBoyForever.exe", 0x5dfc98;    
    
    // in nanoseconds, the level timer that is displayed in the upper left
    uint levelTimer : "SuperMeatBoyForever.exe", 0x5dfd70;

    // in nanoseconds, level timer at the last chunk completion
    uint lastChunkSplitTime : "SuperMeatBoyForever.exe", 0x5dfd78;
    
    // position of the current chunk in the level, so usually 0 to 8
    int currentChunkIndex : "SuperMeatBoyForever.exe", 0x5dfde0;
    
    // 0 = grove, ...
    // careful: does not reset when exiting the savefile, only updated when reentering a chapter
    int currentChapter : "SuperMeatBoyForever.exe", 0x5dd440, 0x0;

    // -1 : not in a level
    // 0 to 5 : light levels
    // 6 to 11 : dark levels
    // 12 : boss fight
    int currentLevel : "SuperMeatBoyForever.exe", 0x5ad000;

    // is set to 1 when entering a level/boss
    // and switches back to 0 only when the level completion is triggered
    int levelNotComplete : "SuperMeatBoyForever.exe", 0x5b10a0;
    
    // on the final boss, second least significant bit is true when meat boy is frozen for animation
    int lastBossFreeze : "SuperMeatBoyForever.exe", 0x5df598, 0x10c;

    // not sure what this is exactly, but the value is 4 when meat boy dies
    int status : "SuperMeatBoyForever.exe", 0x5df598, 0x1c0;
}

startup {
    settings.Add("bosses", true, "Split upon beating bosses.");
    settings.Add("levels", true, "Split upon completing levels.");
    settings.Add("unlocks", false, "Split upon unlocking bosses.");
    settings.Add("chunks", false, "Split upon completing chunks.");
    settings.SetToolTip("chunks",  
        "This includes the small 1.5s chunk at the beginning of the level and excludes the last 1.5s chunk");
    settings.Add("chunkLogging", false, "Log chunk times to a file.");
    settings.SetToolTip("chunkLogging", "The file is stored at [livesplit folder]/smbf_log");

    settings.Add("ilmode", false, "Individual Level Mode (turn off when doing full runs).");
    settings.SetToolTip("ilmode", "Makes the timer start at 0 instead of jumping to whatever the current in-game timer is at in order to adjust for individual level/world runs. Also enables auto-starting the timer whenever any level is entered.");
    
    settings.CurrentDefaultParent = "ilmode";
    settings.Add("ilreset", false, "Auto-reset when exiting any level (for ILs).");
    settings.Add("iwreset", false, "Auto-reset when entering the first level of the world (for IWs).");
    settings.CurrentDefaultParent = null;

    // create log directory and file if they do not exist
    Directory.CreateDirectory("smbf_log");
    if (!File.Exists("smbf_log/chunk_times.csv")) {
        using (StreamWriter sw = File.AppendText("smbf_log/chunk_times.csv"))
            sw.WriteLine("chapter,level,chunk_id,completion_time_milliseconds");
    }

    Func<ProcessModuleWow64Safe, string> CalcModuleHash = (module) => {
        print("Calcuating hash of " + module.FileName);
        byte[] exeHashBytes = new byte[0];
        using (var sha = System.Security.Cryptography.MD5.Create())
        {
            using (var s = File.Open(module.FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                exeHashBytes = sha.ComputeHash(s);
            }
        }
        var hash = exeHashBytes.Select(x => x.ToString("X2")).Aggregate((a, b) => a + b);
        print("Hash: " + hash);
        return hash;
    };
    vars.CalcModuleHash = CalcModuleHash;
}

init {
    var module = modules.Where(m => m.ModuleName == "SuperMeatBoyForever.exe").First();
    var hash = vars.CalcModuleHash(module);
    if (hash == "E5EC4840D24939E0AB5B30EF45DC1518") {
        version = "6201.1266.1561.138 (EGS)";
        print("Version : " + version);

        vars.CHUNKS_ARRAY_BASE = 0x5b9ed8;
        vars.CHUNKS_ARRAY_OFFSET = 0x5e4d00;
        vars.LEVEL_STRUCTURES = 0x5b3360;
    }

    // keeps track of the level count for boss unlock splitting
    // resets to 0 whenever currentChapter changes, increments whenever a level is beaten
    vars.levelCount = 0;

    // Only matters for IL mode, when the timer needs to subtract the framecount of the timer when it started.
    vars.startFrameCount = 0;

    vars.finalBlowSoon = false;

    vars.GetChunkId = (Func<int, int, int, ushort>) ((chapter, level, chunkIndex) => {
        var smbf = modules.Where(m => m.ModuleName == "SuperMeatBoyForever.exe").First().BaseAddress;
        var chunksBase = memory.ReadValue<IntPtr>(smbf + (int)vars.CHUNKS_ARRAY_BASE);
        var chunksBaseOffset = memory.ReadValue<int>(smbf + (int)vars.CHUNKS_ARRAY_OFFSET);
        var chunks = new DeepPointer(
            chunksBase + 8 * chunksBaseOffset, 
            0x78 + 0x9e0 + 0x18
        ).Deref<IntPtr>(game);
        var chunkId = new DeepPointer(
            smbf + (int)vars.LEVEL_STRUCTURES, 
            8 * 5 * chapter + 0x20, 
            0x58 * level + 0x48, 
            4 * chunkIndex
        ).Deref<ushort>(game);
        return chunkId;
    });

    vars.LogTime = (Func<int, int, ushort, uint, bool>) ((chapter, level, chunkId, completionTime) => {
        using (StreamWriter sw = File.AppendText("smbf_log/chunk_times.csv"))
            sw.WriteLine(chapter.ToString() + "," + level.ToString() + "," + chunkId.ToString() + "," + completionTime.ToString());
        return true;
    });
}

update {
    if (old.currentChapter != current.currentChapter)
        vars.levelCount = 0;
    if (current.currentChapter == 4 && current.currentLevel == 12) {
        if (current.status == 4) {
            vars.finalBlowSoon = false;
        }
        else if (old.levelNotComplete == 1 && current.levelNotComplete == 0) {
            vars.finalBlowSoon = true;
        }
    }
}

start {
    vars.startFrameCount = 0;

    if (old.frameCount == 0 && current.frameCount > 0) {
        vars.levelCount = 0;
        vars.finalBlowSoon = false;
        return true;
    }

    if (settings["ilmode"] && old.currentLevel == -1 && current.currentLevel != -1) {
        vars.levelCount = 0;
        vars.finalBlowSoon = false;
        vars.startFrameCount = current.frameCount;
        return true;
    }
}

reset {
    if (old.frameCount > 0 && current.frameCount == 0)
        return true;

    if (settings["ilreset"] && old.currentLevel != -1 && current.currentLevel == -1)
        return true;

    if (settings["iwreset"] && old.currentLevel == -1 && current.currentLevel == 0)
        return true;
}

split {
    if (old.levelNotComplete == 1 && current.levelNotComplete == 0) {
        if (current.currentLevel >= 0 && current.currentLevel < 12) {
            vars.levelCount++;

            if (settings["levels"])
                return true;
            
            if (settings["unlocks"] && vars.levelCount == 4)
                return true;
        }
        if (settings["bosses"] && current.currentLevel == 12 && current.currentChapter != 4)
            return true;
    }

    if (old.currentChunkIndex < current.currentChunkIndex && current.currentLevel >= 0 && current.currentLevel < 12) {
        if (settings["chunkLogging"] && old.currentChunkIndex > 0) {
            var chunkId = vars.GetChunkId(old.currentChapter, old.currentLevel, old.currentChunkIndex);
            uint chunkTime = (current.levelTimer - old.lastChunkSplitTime) / 1000;
            vars.LogTime(old.currentChapter, old.currentLevel, chunkId, chunkTime);
        }
        if (settings["chunks"])
            return true;
    }

    if (current.currentChapter == 4 && current.currentLevel == 12 && vars.finalBlowSoon) {
        bool wasFrozen = (old.lastBossFreeze & 2) == 2;
        bool isFrozen = (current.lastBossFreeze & 2) == 2;
        if (!wasFrozen && isFrozen) {
            return true;
        }
    }
    return false;
}

isLoading {
    return true;  // Just so gameTime works.
}

gameTime {
    if (!settings["ilmode"])
        return TimeSpan.FromSeconds((current.frameCount)/ 60.0);    // 60 frames in a second.
    else
        return TimeSpan.FromSeconds((current.frameCount - vars.startFrameCount)/ 60.0);    // Subtract the time from when the timer started.
}