-- ================================================================
--  Rename LOW / HIGH by Proximity (SAFE)
-- ----------------------------------------------------------------
--  Author      : Oscar "Khanzino"
--  Version     : 1.0
--  Software    : Autodesk 3ds Max
--  Category    : Khanzino Tools
-- ----------------------------------------------------------------
--  Description:
--      Batch tool for baking prep. Renames LOW objects with a
--      base name and numbered suffix (asset_001, asset_002, ...),
--      then matches each LOW to its closest HIGH by bounding box
--      center distance and applies _low / _high suffixes ready to
--      bake in Marmoset, Substance Painter, or any baker.
--
--  Workflow:
--      LOW setup:
--          Select your LOW objects, write a base name, and press
--          "Rename selected LOW bases + store". They get sequential
--          names (asset_001, asset_002, ...) and are auto-stored.
--          Alternatively, if your LOWs are already named, just select
--          them and press "Store already-named LOW objects".
--      HIGH setup:
--          Select your HIGH objects and press
--          "Store selected HIGH objects".
--      Match and rename:
--          Press "Match pairs + add _low/_high". Each LOW is paired
--          with its closest HIGH by bbox center and renamed with
--          _low / _high suffixes, ready to bake.
--
--  Notes:
--      - Pairing is greedy nearest-neighbour by bbox center.
--      - Each HIGH is consumed once, no duplicates.
--      - Layers are restored after renaming.
--      - _low / _high suffixes are stripped only at the END of the
--        name (case-insensitive), so names like "highland_trim_low"
--        cleanly become "highland_trim" without touching "highland".
--      - Spaces in base name or separator trigger a soft warning
--        (most game pipelines dislike them) but never block the
--        user from continuing if they confirm.
--      - Proximity matching uses bounding box center distance.
--      - After renaming, the script selects the matched pairs
--        (low + high) so they are ready to export to your baker.
--        If any objects were left unpaired, those are selected
--        instead so they can be spotted in the viewport.
-- ================================================================

macroScript Rename_LOW_HIGH_By_Distance_SAFE
category:"Khanzino Tools"
tooltip:"Rename LOW/HIGH by proximity SAFE"
buttonText:"Rename LH"
(
    try(destroyDialog RenameLowHighByDistance_SAFE)catch()

    rollout RenameLowHighByDistance_SAFE "Rename LOW / HIGH by Proximity" width:360
    (
        local lowObjects = #()
        local highObjects = #()
        local lowLayers = #()
        local highLayers = #()

        -- ===== UI =====
        group "1. LOW objects"
        (
            label lblBatchTitle "Batch rename selected LOWs:"
            editText edtBaseName "Base name:" text:"asset" width:310
            editText edtSeparator "Separator:" text:"_" width:310
            spinner spnStart "Start:" range:[0,999999,1] type:#integer fieldwidth:70
            checkbox chkSortByName "Sort by current name first" checked:true
            button btnBatchRenameLow "Rename selected LOW bases + store" width:310 height:32
            label lblBatch "Example: asset_001"

            label lblOptional "LOWs already named?"
            button btnGetLow "Store selected LOW objects" width:310
            label lblLow "Stored LOWs: 0"
        )

        group "2. HIGH objects"
        (
            button btnGetHigh "Store selected HIGH objects" width:310
            label lblHigh "Stored HIGHs: 0"
        )

        group "3. Match and rename"
        (
            label lblStatus "LOWs: 0  /  HIGHs: 0  /  Not ready"
            button btnRename "Match pairs + add _low/_high" width:310 height:35 enabled:false
        )

        -- ===== Helpers =====

        -- Comparator used by qsort to sort nodes alphabetically.
        fn compareNodeNames a b =
        (
            stricmp a.name b.name
        )

        -- Builds a name like "asset_001" given prefix, separator and index.
        fn buildBaseName prefix sep idx =
        (
            prefix + sep + (formattedPrint idx format:"03d")
        )

        -- Updates the preview label in the UI as the user types.
        fn updateExample =
        (
            lblBatch.text = "Example: " + (buildBaseName edtBaseName.text edtSeparator.text (spnStart.value as integer))
        )

        -- Strips _low / _high suffixes ONLY at the end of the name (case-insensitive).
        -- Loops in case multiple suffixes are stacked (e.g. "Chair_low_HIGH" -> "Chair").
        -- Names like "highland_table" or "lowpoly_test" stay untouched because the
        -- matching token is "_low" / "_high" anchored to the end of the string.
        fn cleanName n =
        (
            local result = n
            local changed = true

            while changed do
            (
                changed = false
                local len = result.count

                -- Try "_low" at the end (4 chars)
                if len >= 4 do
                (
                    local tail4 = toLower (substring result (len - 3) 4)
                    if tail4 == "_low" do
                    (
                        result = substring result 1 (len - 4)
                        changed = true
                    )
                )

                -- Try "_high" at the end (5 chars), only if "_low" didn't strip
                if not changed and result.count >= 5 do
                (
                    local len2 = result.count
                    local tail5 = toLower (substring result (len2 - 4) 5)
                    if tail5 == "_high" do
                    (
                        result = substring result 1 (len2 - 5)
                        changed = true
                    )
                )
            )

            result
        )

        -- Returns the node in arr closest to obj by bounding box center.
        fn closestObject obj arr =
        (
            local bestObj = undefined
            local bestDist = 999999999.0

            for h in arr do
            (
                if isValidNode h do
                (
                    local d = distance obj.center h.center
                    if d < bestDist do
                    (
                        bestDist = d
                        bestObj = h
                    )
                )
            )

            bestObj
        )

        -- Re-adds each object to its original layer.
        -- Renaming can sometimes shuffle layer membership, so we restore it.
        fn restoreOriginalLayers objs layers =
        (
            for i = 1 to objs.count do
            (
                if isValidNode objs[i] and layers[i] != undefined do
                (
                    try(layers[i].addNode objs[i])catch()
                )
            )
        )

        -- Appends up to maxShow names from arr to msg, with an
        -- ellipsis line if there are more. Returns the updated string.
        fn appendNameList msg arr maxShow =
        (
            local out = msg
            local shown = 0

            for i = 1 to arr.count do
            (
                if shown >= maxShow do exit
                out += "\n  - " + arr[i]
                shown += 1
            )

            if arr.count > maxShow do
            (
                out += "\n  ... and " + ((arr.count - maxShow) as string) + " more"
            )

            out
        )

        -- Counts only valid (not deleted) nodes in an array.
        fn countValidNodes arr =
        (
            local c = 0
            for n in arr do (if isValidNode n do c += 1)
            c
        )

        -- Updates the status label and enables/disables the rename button.
        -- Uses countValidNodes so deleted objects don't inflate the count.
        fn updateStatus =
        (
            local lc = countValidNodes lowObjects
            local hc = countValidNodes highObjects
            local isReady = lc > 0 and hc > 0
            btnRename.enabled = isReady

            local statusStr = "LOWs: " + (lc as string) + "  /  HIGHs: " + (hc as string) + "  /  "

            if not isReady then
            (
                statusStr += "Not ready"
            )
            else if lc != hc then
            (
                statusStr += "Ready, unmatched possible"
            )
            else
            (
                statusStr += "Ready"
            )

            lblStatus.text = statusStr
        )

        -- ===== UI event handlers =====

        on edtBaseName changed txt do (updateExample())
        on edtSeparator changed txt do (updateExample())
        on spnStart changed val do (updateExample())

        -- Batch rename selected objects with prefix + index,
        -- then automatically store them as the LOW set.
        on btnBatchRenameLow pressed do
        (
            local objs = selection as array

            if objs.count == 0 then
            (
                messageBox "Select the LOW objects first."
            )
            else if edtBaseName.text == "" then
            (
                messageBox "Write a base name first."
            )
            else
            (
                -- Soft warning: spaces are allowed but not recommended for
                -- game pipelines. Ask the user to confirm before proceeding.
                local proceed = true

                if (findString edtBaseName.text " ") != undefined do
                (
                    if not (queryBox (
                        "Base name contains spaces.\n\n" +
                        "Spaces in object names can cause issues in many " +
                        "game pipelines (engines, bakers, export formats).\n\n" +
                        "Continue anyway?"
                    ) title:"Spaces detected") do
                    (
                        proceed = false
                    )
                )

                if proceed and (findString edtSeparator.text " ") != undefined do
                (
                    if not (queryBox (
                        "Separator contains spaces.\n\n" +
                        "This will produce object names with spaces inside, " +
                        "which can cause issues downstream.\n\n" +
                        "Continue anyway?"
                    ) title:"Spaces detected") do
                    (
                        proceed = false
                    )
                )

                if proceed do
                (
                    undo "Batch Rename LOW Base Names" on
                    (
                        if chkSortByName.checked do
                        (
                            qsort objs compareNodeNames
                        )

                        local prefix = edtBaseName.text
                        local sep = edtSeparator.text
                        local startNum = spnStart.value as integer
                        local conflicts = #()

                        -- Detect target names that already exist on non-selected nodes.
                        for i = 1 to objs.count do
                        (
                            local targetName = buildBaseName prefix sep (startNum + i - 1)
                            local existingNode = getNodeByName targetName

                            if existingNode != undefined and (findItem objs existingNode) == 0 do
                            (
                                append conflicts targetName
                            )
                        )

                        if conflicts.count > 0 then
                        (
                            messageBox (
                                "Some target names already exist on non-selected objects.\n\n" +
                                "First conflict: " + conflicts[1] + "\n\n" +
                                "Use another base name, another start number, or rename those objects first."
                            )
                        )
                        else
                        (
                            local stamp = timestamp() as string
                            local renamedCount = 0

                            -- Two-pass rename: first to unique temp names to avoid
                            -- internal collisions, then to the final names.
                            for i = 1 to objs.count do
                            (
                                if isValidNode objs[i] do
                                (
                                    objs[i].name = "__KHZ_TMP_RENAME_" + stamp + "_" + (formattedPrint i format:"04d")
                                )
                            )

                            for i = 1 to objs.count do
                            (
                                if isValidNode objs[i] do
                                (
                                    objs[i].name = buildBaseName prefix sep (startNum + i - 1)
                                    renamedCount += 1
                                )
                            )

                            -- Auto-store as LOW set for the next step.
                            lowObjects = objs
                            lowLayers = #()

                            for obj in lowObjects do
                            (
                                append lowLayers obj.layer
                            )

                            lblLow.text = "Stored LOWs: " + (lowObjects.count as string)
                            updateStatus()
                            lblBatch.text = "Renamed LOW bases: " + (renamedCount as string)

                            messageBox (
                                "Renamed selected LOW base names: " + (renamedCount as string) + "\n\n" +
                                "No _low suffix was added.\n" +
                                "These objects are now stored as LOW objects."
                            )
                        )
                    )
                )
            )
        )

        -- Store currently selected nodes as the LOW set.
        -- Used when LOW objects are already correctly named.
        on btnGetLow pressed do
        (
            lowObjects = selection as array
            lowLayers = #()

            for obj in lowObjects do
            (
                append lowLayers obj.layer
            )

            lblLow.text = "Stored LOWs: " + (lowObjects.count as string)
            updateStatus()
        )

        -- Store currently selected nodes as the HIGH set.
        on btnGetHigh pressed do
        (
            highObjects = selection as array
            highLayers = #()

            for obj in highObjects do
            (
                append highLayers obj.layer
            )

            lblHigh.text = "Stored HIGHs: " + (highObjects.count as string)
            updateStatus()
        )

        -- Pair each LOW with its closest HIGH by bbox center
        -- and rename them with _low / _high suffixes.
        --
        -- Safety phases:
        --   1. Compute pairs (matching only, no rename yet).
        --   2. Validate: empty bases, internal duplicates, external conflicts.
        --   3. Two-pass rename: temp names first, then final names. This
        --      avoids transient collisions inside the working set.
        on btnRename pressed do
        (
            -- Refresh status before acting, in case objects were deleted
            -- after being stored.
            updateStatus()

            if lowObjects.count == 0 then
            (
                messageBox "Store the LOW objects first using one of the LOW setup buttons."
            )
            else if highObjects.count == 0 then
            (
                messageBox "Store the HIGH objects first using \"Store selected HIGH objects\"."
            )
            else
            (
                -- Overlap check: no node can be its own pair.
                local overlap = #()
                for l in lowObjects do
                (
                    if isValidNode l and (findItem highObjects l) > 0 do
                    (
                        append overlap l
                    )
                )

                if overlap.count > 0 then
                (
                    local overlapNames = for o in overlap collect o.name
                    local overlapMsg = "Some objects are stored as BOTH LOW and HIGH: " + \
                                       (overlap.count as string)
                    overlapMsg = appendNameList overlapMsg overlapNames 8
                    overlapMsg += "\n\nRe-store the LOW and HIGH sets making sure " + \
                                  "they don't overlap, then try again."
                    messageBox overlapMsg
                )
                else
                (
                    -- ===== Phase 1: compute pairs without renaming =====
                    local remainingHighs = for h in highObjects where isValidNode h collect h
                    local pairs = #()
                    local unmatchedLowNodes = #()
                    local unmatchedLowNames = #()
                    local emptyBases = #()

                    for l in lowObjects do
                    (
                        if isValidNode l do
                        (
                            local h = closestObject l remainingHighs

                            if h != undefined then
                            (
                                local base = cleanName l.name

                                if base == "" then
                                (
                                    append emptyBases l.name
                                )
                                else
                                (
                                    append pairs #(l, h, base)
                                    deleteItem remainingHighs (findItem remainingHighs h)
                                )
                            )
                            else
                            (
                                append unmatchedLowNames l.name
                                append unmatchedLowNodes l
                            )
                        )
                    )

                    -- ===== Phase 2: validate =====

                    if emptyBases.count > 0 then
                    (
                        local emptyMsg = "Some LOW objects have names that become empty after stripping _low/_high: " + \
                                         (emptyBases.count as string)
                        emptyMsg = appendNameList emptyMsg emptyBases 8
                        emptyMsg += "\n\nRename those objects to have a real base name " + \
                                    "(not just \"_low\" or \"_high\"), then try again."
                        messageBox emptyMsg
                    )
                    else
                    (
                        -- Internal duplicates: two LOWs that clean to the same base.
                        -- Comparison is case-insensitive because many pipelines (engines,
                        -- bakers, filesystems on Windows) treat "Chair_low" and "chair_low"
                        -- as the same name.
                        local seenBaseKeys = #()
                        local internalDuplicates = #()

                        for p in pairs do
                        (
                            local base = p[3]
                            local baseKey = toLower base
                            if (findItem seenBaseKeys baseKey) != 0 then
                            (
                                if (findItem internalDuplicates base) == 0 do
                                    append internalDuplicates base
                            )
                            else
                            (
                                append seenBaseKeys baseKey
                            )
                        )

                        if internalDuplicates.count > 0 then
                        (
                            local dupMsg = "Multiple LOW objects would end up with the same base name: " + \
                                           (internalDuplicates.count as string)
                            dupMsg = appendNameList dupMsg internalDuplicates 8
                            dupMsg += "\n\nThis happens when two LOWs clean to the same base " + \
                                      "(e.g. \"Chair\" and \"Chair_low\"). Rename one of them, then try again."
                            messageBox dupMsg
                        )
                        else
                        (
                            -- External conflicts: target names existing on objects
                            -- that will NOT be renamed (so they will not get out of the way).
                            -- Paired nodes go through temp rename, so a name collision
                            -- with them during the final pass is safe. Anything else is
                            -- a real conflict, even if it lives inside lowObjects/highObjects
                            -- as an unmatched node.
                            local pairedNodes = #()
                            for p in pairs do
                            (
                                append pairedNodes p[1]
                                append pairedNodes p[2]
                            )

                            local nameConflicts = #()

                            for p in pairs do
                            (
                                local base = p[3]
                                local targetLow  = base + "_low"
                                local targetHigh = base + "_high"

                                local existingLow  = getNodeByName targetLow
                                local existingHigh = getNodeByName targetHigh

                                if existingLow != undefined and (findItem pairedNodes existingLow) == 0 do
                                (
                                    if (findItem nameConflicts targetLow) == 0 do
                                        append nameConflicts targetLow
                                )

                                if existingHigh != undefined and (findItem pairedNodes existingHigh) == 0 do
                                (
                                    if (findItem nameConflicts targetHigh) == 0 do
                                        append nameConflicts targetHigh
                                )
                            )

                            if nameConflicts.count > 0 then
                            (
                                local conflictMsg = "Some target names already exist on objects that will not be renamed: " + \
                                                    (nameConflicts.count as string)
                                conflictMsg = appendNameList conflictMsg nameConflicts 8
                                conflictMsg += "\n\nRename or remove those objects first, then try again."
                                messageBox conflictMsg
                            )
                            else
                            (
                                -- ===== Phase 3: two-pass rename =====
                                undo "Rename LOW/HIGH by Distance SAFE" on
                                (
                                    local stamp = timestamp() as string
                                    local matchedNodes = #()

                                    -- Pass 1: temp names on all paired nodes.
                                    for i = 1 to pairs.count do
                                    (
                                        local p = pairs[i]
                                        local l = p[1]
                                        local h = p[2]

                                        if isValidNode l do
                                        (
                                            l.name = "__KHZ_TMP_LOW_" + stamp + "_" + (formattedPrint i format:"04d")
                                        )
                                        if isValidNode h do
                                        (
                                            h.name = "__KHZ_TMP_HIGH_" + stamp + "_" + (formattedPrint i format:"04d")
                                        )
                                    )

                                    -- Pass 2: final names.
                                    for p in pairs do
                                    (
                                        local l = p[1]
                                        local h = p[2]
                                        local base = p[3]

                                        if isValidNode l do
                                        (
                                            l.name = base + "_low"
                                            append matchedNodes l
                                        )
                                        if isValidNode h do
                                        (
                                            h.name = base + "_high"
                                            append matchedNodes h
                                        )
                                    )

                                    local unmatchedHighNodes = for h in remainingHighs where isValidNode h collect h
                                    local unmatchedHighNames = for h in unmatchedHighNodes collect h.name

                                    restoreOriginalLayers lowObjects lowLayers
                                    restoreOriginalLayers highObjects highLayers

                                    local hasUnmatched = (unmatchedLowNodes.count > 0) or (unmatchedHighNodes.count > 0)

                                    if hasUnmatched then
                                    (
                                        clearSelection()
                                        for n in unmatchedLowNodes do (if isValidNode n do selectMore n)
                                        for n in unmatchedHighNodes do (if isValidNode n do selectMore n)
                                    )
                                    else
                                    (
                                        clearSelection()
                                        for n in matchedNodes do (if isValidNode n do selectMore n)
                                    )

                                    local msg = "Renamed: " + (pairs.count as string) + " pairs.\nLayers restored."
                                    local maxShow = 8

                                    if hasUnmatched do
                                    (
                                        msg += "\n\n** Unmatched objects have been selected in the viewport. **"
                                    )

                                    if unmatchedLowNames.count > 0 do
                                    (
                                        msg += "\n\nUnmatched LOW objects: " + (unmatchedLowNames.count as string)
                                        msg = appendNameList msg unmatchedLowNames maxShow
                                    )

                                    if unmatchedHighNames.count > 0 do
                                    (
                                        msg += "\n\nUnmatched HIGH objects: " + (unmatchedHighNames.count as string)
                                        msg = appendNameList msg unmatchedHighNames maxShow
                                    )

                                    messageBox msg
                                )
                            )
                        )
                    )
                )
            )
        )
    )

    createDialog RenameLowHighByDistance_SAFE
)
