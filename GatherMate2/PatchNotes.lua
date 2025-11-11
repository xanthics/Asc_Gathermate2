local GatherMate = LibStub("AceAddon-3.0"):GetAddon("GatherMate2")
local gatherNotes = {
    {"Version 1.0.7", "2025/11/10"},
        "Added patchnotes module from AtlasLoot",
        "Added Data Sharing Options",
        "Added Tracking for more HR nodes",
}

function GatherMate:PatchNotes()
    self:InitializeNewsFrame(self.db.profile, gatherNotes, "GatherMate2")
end