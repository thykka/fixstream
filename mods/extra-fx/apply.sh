# SPDX-License-Identifier: GPL-3.0-or-later
# Extra FX on Shift + FX select buttons. Sourced by patch.sh.
#   1. Engine: NH08 config /Configuration/NHFx False (26 DJ FX instead of 4)
#   2. NH08_Controller_Assignments.qml: the DJFxSelect block is replaced by fx-select.qml
#      (Shift cycles a list of four extra effects per button)

MOD="$ROOT/mods/extra-fx"
ENGINE=/usr/Engine/Engine
MAPPING=/usr/Engine/AssignmentFiles/PresetAssignmentFiles/NH08/NH08_Controller_Assignments.qml

dbg "dump $ENGINE $FWORK/Engine.in"
dbg "dump $MAPPING $FWORK/mapping.in"

python3 -I "$ROOT/tools/engine-config.py" set "$FWORK/Engine.in" "$FWORK/Engine" NH08 /Configuration/NHFx False

python3 -I "$ROOT/tools/qml-edit.py" block "$FWORK/mapping.in" "$FWORK/mapping" 'DJFxSelect {' "$MOD/fx-select.qml"
python3 -I "$ROOT/tools/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import InputAssignment 0.1' 'import ControlSurfaceModules 0.1'
python3 -I "$ROOT/tools/qml-edit.py" import "$FWORK/mapping" "$FWORK/mapping" 'import OutputAssignment 0.1' 'import InputAssignment 0.1'

replace "$FWORK/Engine" "$ENGINE"
replace "$FWORK/mapping" "$MAPPING"
