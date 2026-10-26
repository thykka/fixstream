# SPDX-License-Identifier: GPL-3.0-or-later
# Extra FX. Sourced by patch.sh.
#   1. Engine: NH08 config audio.fx.hasDJFx = 1, hasLimitedTouchFx kept, hasNHFx = 0
#      (engine-patch.py, patch dj-fx); the DJ FX list instead of the four NH FX
#   2. NH08_Controller_Assignments.qml: the DJFxSelect block is replaced by fx-select.qml (Shift cycles a list per button)
# Applies to stock files or to the beat jump mod's output; the edits don't overlap.

ENGINE=/usr/Engine/Engine
MAPPING=/usr/Engine/AssignmentFiles/PresetAssignmentFiles/NH08/NH08_Controller_Assignments.qml

# engine-patch.py accepts only the stock Engine plus its known patches (beat jump's)
dbg "dump $ENGINE $FWORK/Engine.in"
dbg "dump $MAPPING $FWORK/mapping.in"

python3 -I "$TOOLS/engine-patch.py" apply "$FWORK/Engine.in" "$FWORK/Engine" dj-fx
python3 -I "$TOOLS/qml-edit.py" block "$FWORK/mapping.in" "$FWORK/mapping" 'DJFxSelect {' "$MOD/fx-select.qml"
# fx-select.qml uses ValueNoteAssignment (InputAssignment) and OutputAssignment; the beat jump mod already imports both
python3 -I "$TOOLS/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import InputAssignment 0.1' 'import Planck 1.0'
python3 -I "$TOOLS/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import OutputAssignment 0.1' 'import InputAssignment 0.1'

replace "$FWORK/Engine" "$ENGINE"
replace "$FWORK/mapping" "$MAPPING"
