dofile("setupTests.lua")
local stub = require("luassert.stub")

describe("native tracker options", function()
    local originals
    local QuestieOptionsEngine, tracker, compat, visibility, trackerUtils
    local isVoiceOverLoadedStub, isSpokenLoadedStub

    -- Visibility is decided once when the tab is defined, so each case defines the tab after setting up the addons.
    local function LoadTab()
        dofile("Modules/Options/NativeOptions/NativeOptionsTracker.lua")
        return QuestieOptionsEngine.tabs.tracker:Initialize().items
    end

    before_each(function()
        originals = {
            LibStub = _G.LibStub,
            QuestLogExFrame = _G.QuestLogExFrame,
            ClassicQuestLog = _G.ClassicQuestLog,
            QuestLogFrame = _G.QuestLogFrame,
            QuestMapFrame = _G.QuestMapFrame,
        }
        _G.QuestLogExFrame = nil
        _G.ClassicQuestLog = nil
        _G.QuestLogFrame = nil
        _G.QuestMapFrame = {IsShown = function() return true end}
        _G.LibStub = function() return {HashTable = function() return {} end} end
        Questie.db = {profile = {}, char = {}}
        QuestieOptionsEngine = QuestieLoader:ImportModule("QuestieOptionsEngine")
        QuestieOptionsEngine.tabs = {}
        tracker = QuestieLoader:ImportModule("QuestieTracker")
        tracker.Update = spy.new(function() end)
        tracker.UpdateFormatting = spy.new(function() end)
        compat = QuestieLoader:ImportModule("QuestieCompat")
        compat.QuestLog_Update = spy.new(function() end)
        visibility = QuestieLoader:ImportModule("CommsVisibility")
        visibility.ScheduleSnapshot = spy.new(function() end)
        trackerUtils = QuestieLoader:ImportModule("TrackerUtils")
        trackerUtils.IsTomTomAvailable = function() return false end
        trackerUtils.IsVoiceOverLoaded = trackerUtils.IsVoiceOverLoaded or function() end
        trackerUtils.IsSpokenLoaded = trackerUtils.IsSpokenLoaded or function() end
        isVoiceOverLoadedStub = stub(trackerUtils, "IsVoiceOverLoaded", function() return false end)
        isSpokenLoadedStub = stub(trackerUtils, "IsSpokenLoaded", function() return false end)
        dofile("Modules/Tracker/TrackerShortcuts.lua")
    end)

    after_each(function()
        isVoiceOverLoadedStub:revert()
        isSpokenLoadedStub:revert()
        _G.LibStub = originals.LibStub
        _G.QuestLogExFrame = originals.QuestLogExFrame
        _G.ClassicQuestLog = originals.ClassicQuestLog
        _G.QuestLogFrame = originals.QuestLogFrame
        _G.QuestMapFrame = originals.QuestMapFrame
    end)

    it("shows TomTom integration options only while TomTom is available", function()
        trackerUtils.IsTomTomAvailable = function() return false end
        assert.is_false(LoadTab().group_quests.items.group_shortcuts.items.setTomTom.visible)

        trackerUtils.IsTomTomAvailable = function() return true end

        assert.is_true(LoadTab().group_quests.items.group_shortcuts.items.setTomTom.visible)
    end)

    it("should show the follow super tracking option only when super tracking is supported", function()
        local isSuperTrackingSupportedStub = stub(compat, "IsSuperTrackingSupported", function() return false end)
        local visibleWithoutSupport = LoadTab().followSuperTracking.visible
        isSuperTrackingSupportedStub.invokes(function() return true end)
        local visibleWithSupport = LoadTab().followSuperTracking.visible
        isSuperTrackingSupportedStub:revert()

        assert.is_false(visibleWithoutSupport)
        assert.is_true(visibleWithSupport)
    end)

    it("should change the follow super tracking setting", function()
        Questie.db.profile.trackerFollowSuperTracking = false
        local followSuperTracking = LoadTab().followSuperTracking

        followSuperTracking.set(nil, true)

        assert.is_true(followSuperTracking.get())
        assert.is_true(Questie.db.profile.trackerFollowSuperTracking)
    end)

    it("should keep the follow super tracking option enabled while the tracker is disabled", function()
        Questie.db.profile.trackerEnabled = false

        local followSuperTracking = LoadTab().followSuperTracking

        assert.is_nil(followSuperTracking.enabled)
    end)

    it("should show the sticky VoiceOver frame option only when VoiceOver is used", function()
        assert.is_false(LoadTab().group_tracker_window.items.stickyVoiceOverFrame.visible)

        isVoiceOverLoadedStub.returns(true)

        assert.is_true(LoadTab().group_tracker_window.items.stickyVoiceOverFrame.visible)
    end)

    it("should show the play buttons option only when VoiceOver or Spoken is used", function()
        assert.is_false(LoadTab().group_tracker_window.items.showPlayButtons.visible)

        isSpokenLoadedStub.returns(true)

        assert.is_true(LoadTab().group_tracker_window.items.showPlayButtons.visible)
    end)

    it("should show the play buttons option when only VoiceOver is used", function()
        isVoiceOverLoadedStub.returns(true)

        assert.is_true(LoadTab().group_tracker_window.items.showPlayButtons.visible)
    end)

    it("should change the play buttons setting and update the tracker", function()
        Questie.db.profile.trackerShowPlayButtons = true
        local showPlayButtons = LoadTab().group_tracker_window.items.showPlayButtons

        showPlayButtons.set(nil, false)

        assert.is_false(showPlayButtons.get())
        assert.is_false(Questie.db.profile.trackerShowPlayButtons)
        assert.spy(tracker.Update).was.called_with(tracker)
    end)

    it("should change the share quest shortcut", function()
        local shareQuest = LoadTab().group_quests.items.group_shortcuts.items.shareQuest

        shareQuest.set("altleft")

        assert.are_same("altleft", shareQuest.get())
        assert.are_same("altleft", Questie.db.profile.trackerbindShareQuest)
    end)

    it("disables the other action when a shortcut dropdown takes its click", function()
        local shortcutDropdowns = {
            openQuestLog = "trackerbindOpenQuestLog",
            untrackQuest = "trackerbindUntrack",
            shareQuest = "trackerbindShareQuest",
            setTomTom = "trackerbindSetTomTom",
        }
        local items = LoadTab().group_quests.items.group_shortcuts.items

        for dropdown, setting in pairs(shortcutDropdowns) do
            for _, otherSetting in pairs(shortcutDropdowns) do
                Questie.db.profile[otherSetting] = otherSetting == setting and "disabled" or "altright"
            end

            items[dropdown].set("altright")

            for _, otherSetting in pairs(shortcutDropdowns) do
                assert.are_same(otherSetting == setting and "altright" or "disabled", Questie.db.profile[otherSetting], dropdown)
            end
        end
    end)

    it("updates the tracker and publishes visibility when only the modern log exists", function()
        LoadTab().group_quests.items.autoTrackQuests.set(nil, true)

        assert.is_true(Questie.db.profile.autoTrackQuests)
        assert.are.same({}, Questie.db.char.TrackedQuests)
        assert.spy(tracker.Update).was.called_with(tracker)
        assert.spy(visibility.ScheduleSnapshot).was.called_with(visibility, "AUTO_TRACK_QUESTS")
        assert.spy(compat.QuestLog_Update).was.not_called()
    end)

    describe("ignore Blizzard tracker", function()
        local originalForever

        before_each(function()
            originalForever = Questie.IsForever
        end)

        after_each(function()
            Questie.IsForever = originalForever
        end)

        it("should be listed after Auto Track Quests and Show Quest Level", function()
            local items = LoadTab().group_quests.items

            assert.is_true(items.autoTrackQuests.order < items.ignoreBlizzardTracker.order)
            assert.is_true(items.showQuestLevels.order < items.ignoreBlizzardTracker.order)
            assert.is_true(items.ignoreBlizzardTracker.order < items.listAchievementsFirst.order)
        end)

        it("should only be visible on Forever, whose quest log keeps its own watch limit", function()
            Questie.IsForever = false
            local visibleOnClassic = LoadTab().group_quests.items.ignoreBlizzardTracker.visible
            Questie.IsForever = true
            local visibleOnForever = LoadTab().group_quests.items.ignoreBlizzardTracker.visible

            assert.is_false(visibleOnClassic)
            assert.is_true(visibleOnForever)
        end)

        it("should only be enabled while Auto Track Quests is enabled", function()
            Questie.db.profile.trackerEnabled = true
            local option = LoadTab().group_quests.items.ignoreBlizzardTracker

            Questie.db.profile.autoTrackQuests = true
            assert.is_true(option.enabled())
            Questie.db.profile.autoTrackQuests = false
            assert.is_false(option.enabled())
        end)

        it("should track quests unchecked in the Blizzard quest log again when enabled", function()
            Questie.db.char.AutoUntrackedQuests = {[91741] = true}

            LoadTab().group_quests.items.ignoreBlizzardTracker.set(nil, true)

            assert.is_true(Questie.db.profile.trackerIgnoreBlizzardTracker)
            assert.are.same({}, Questie.db.char.AutoUntrackedQuests)
            assert.spy(tracker.Update).was.called_with(tracker)
            assert.spy(visibility.ScheduleSnapshot).was.called_with(visibility, "IGNORE_BLIZZARD_TRACKER")
        end)

        it("should keep untracked quests untracked when disabled", function()
            Questie.db.profile.trackerIgnoreBlizzardTracker = true
            Questie.db.char.AutoUntrackedQuests = {[91741] = true}

            LoadTab().group_quests.items.ignoreBlizzardTracker.set(nil, false)

            assert.is_false(Questie.db.profile.trackerIgnoreBlizzardTracker)
            assert.is_true(Questie.db.char.AutoUntrackedQuests[91741])
            assert.spy(tracker.Update).was.called_with(tracker)
        end)
    end)

    -- Quest-log checks skip unchanged quests, so this setting must request the quest lines itself.
    it("lays out the tracker when always showing it expands a minimized tracker", function()
        Questie.db.char.isTrackerExpanded = false

        LoadTab().group_tracker_window.items.group_header.items.alwaysShowTracker.set(nil, true)

        assert.is_true(Questie.db.char.isTrackerExpanded)
        assert.spy(tracker.Update).was.called_with(tracker)
        assert.spy(tracker.UpdateFormatting).was.called_with(tracker)
    end)

    -- The sliders call the setter with userInput during a drag, and without it when the drag ended.
    describe("tracker size ratios", function()
        local TrackerBaseFrame

        before_each(function()
            TrackerBaseFrame = QuestieLoader:ImportModule("TrackerBaseFrame")
            Questie.db.profile = {
                TrackerHeight = 0,
                TrackerWidth = 0,
                trackerBackdropEnabled = false,
                currentBackdropEnabled = false,
                trackerBorderEnabled = false,
                currentBorderEnabled = false,
                trackerBackdropFader = true,
                currentBackdropFader = true,
            }
        end)

        for key, profileKey in pairs({trackerHeightRatio = "trackerHeightRatio", trackerWidthRatio = "trackerWidthRatio"}) do
            it("should show the sizing backdrop while dragging " .. key, function()
                LoadTab().group_tracker_window.items[key].set(nil, 50, true)

                assert.are.equal(0.5, Questie.db.profile[profileKey])
                assert.is_true(TrackerBaseFrame.isSizing)
                assert.is_true(Questie.db.profile.trackerBackdropEnabled)
                assert.is_true(Questie.db.profile.trackerBorderEnabled)
                assert.is_false(Questie.db.profile.trackerBackdropFader)
            end)

            it("should restore the user's backdrop when dragging " .. key .. " ended", function()
                local option = LoadTab().group_tracker_window.items[key]
                option.set(nil, 50, true)

                option.set(nil, 50, false)

                assert.is_false(TrackerBaseFrame.isSizing)
                assert.is_false(Questie.db.profile.trackerBackdropEnabled)
                assert.is_false(Questie.db.profile.trackerBorderEnabled)
                assert.is_true(Questie.db.profile.trackerBackdropFader)
            end)
        end
    end)
end)
