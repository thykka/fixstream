# SPDX-License-Identifier: GPL-3.0-or-later
# Beat jump. Sourced by patch.sh.
#   1. Engine: NH08 config /Configuration/Deck/HasBeatJump True
#   2. NH08_Controller_Assignments.qml: the PitchBend block is replaced by pitch-buttons.qml
#      (Auto Loop pad mode: beat jump, Shift halves/doubles the size; other modes: stock nudge/range)

MOD="$ROOT/mods/beat-jump"
ENGINE=/usr/Engine/Engine
MAPPING=/usr/Engine/AssignmentFiles/PresetAssignmentFiles/NH08/NH08_Controller_Assignments.qml

dbg "dump $ENGINE $FWORK/Engine.in"
dbg "dump $MAPPING $FWORK/mapping.in"

python3 -I "$ROOT/tools/engine-config.py" set "$FWORK/Engine.in" "$FWORK/Engine" NH08 /Configuration/Deck/HasBeatJump True

python3 -I "$ROOT/tools/qml-edit.py" block "$FWORK/mapping.in" "$FWORK/mapping" 'PitchBend {' "$MOD/pitch-buttons.qml"
python3 -I "$ROOT/tools/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import InputAssignment 0.1' 'import ControlSurfaceModules 0.1'

replace "$FWORK/Engine" "$ENGINE"
replace "$FWORK/mapping" "$MAPPING"
