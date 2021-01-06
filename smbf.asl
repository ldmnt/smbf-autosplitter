state("SuperMeatBoyForever") {
    // as a number of frames (at 60 fps), the speedrun timer that is displayed in the upper right
    uint frameCount : "SuperMeatBoyForever.exe", 0x5dfc98;    
    
    // in nanoseconds, the level timer that is displayed in the upper left
    uint levelTimer : "SuperMeatBoyForever.exe", 0x5dfd70;    
    
    // 0 = grove, ...
    // careful: does not reset when exiting the savefile, only updated when reentering a chapter
    int currentChapter : "SuperMeatBoyForever.exe", 0x5dd440, 0x0;

    // -1 : not in a level
    // 0 to 5 : light levels
    // 6 to 11 : dark levels
    // 12 : boss fight
    int currentLevel : "SuperMeatBoyForever.exe", 0x5ad000;

    // inside a level : 0 if not completed, 8 at level completion
    // inside a boss fight : 1 if not beaten yet, 0 after beating the boss
    byte completionIndicator : "SuperMeatBoyForever.exe", 0x5dfd64;
}

startup {
    settings.Add("bosses", true, "Split upon beating bosses.");
    settings.Add("levels", true, "Split upon completing levels");
}

start {
    return old.frameCount == 0 && current.frameCount > 0;
}

reset {
    return old.frameCount > 0 && current.frameCount == 0;
}

split {
    if (settings["levels"] && old.completionIndicator == 0 && current.completionIndicator == 8) {
        return current.currentLevel >= 0 && current.currentLevel < 12;
    }
    if (settings["bosses"] && old.completionIndicator == 1 && current.completionIndicator == 0) {
        return current.currentLevel == 12;
    }
    return false;
}

isLoading {
    return true;  // Just so gameTime works.
}

gameTime {
    return TimeSpan.FromSeconds(current.frameCount / 60.0);    // 60 frames in a second.
}