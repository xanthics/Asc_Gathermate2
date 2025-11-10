local GatherMate = LibStub("AceAddon-3.0"):GetAddon("GatherMate2")
local patchNotes = {
    {"Version 1.0.7", "2025/11/10"},
        "Added patchnotes module from AtlasLoot",
        "Added Data Sharing Options",
}

function GatherMate:PatchNotes()
    self:InitializeNewsFrame(self.db.profile, patchNotes, "GatherMate2")
end