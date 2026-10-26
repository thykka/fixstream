# SPDX-License-Identifier: GPL-3.0-or-later
# Beat jump. Sourced by patch.sh.
#   1. Engine: NH08 config audio.deck.hasBeatJump = 1 (engine-patch.py, patch beat-jump)
#   2. NH08_Controller_Assignments.qml: the PitchBend block is replaced by pitch-buttons.qml
#      (Auto Loop pad mode: beat jump, Shift halves/doubles the size; other modes: stock nudge/range)

ENGINE=/usr/Engine/Engine
MAPPING=/usr/Engine/AssignmentFiles/PresetAssignmentFiles/NH08/NH08_Controller_Assignments.qml

# engine-patch.py accepts only the stock Engine plus its known patches
dbg "dump $ENGINE $FWORK/Engine.in"
dbg "dump $MAPPING $FWORK/mapping.in"

python3 -I "$TOOLS/engine-patch.py" apply "$FWORK/Engine.in" "$FWORK/Engine" beat-jump
python3 -I "$TOOLS/qml-edit.py" block "$FWORK/mapping.in" "$FWORK/mapping" 'PitchBend {' "$MOD/pitch-buttons.qml"
python3 -I "$TOOLS/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import InputAssignment 0.1' 'import Planck 1.0'
python3 -I "$TOOLS/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import OutputAssignment 0.1' 'import InputAssignment 0.1'

replace "$FWORK/Engine" "$ENGINE"
replace "$FWORK/mapping" "$MAPPING"
