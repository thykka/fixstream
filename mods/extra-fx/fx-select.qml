	// fixstream extra-fx mod: replaces DJFxSelect.
	// FX select buttons: stock effect; Shift: the first effect of the button's list, each further Shift press the next.
	// Needs /Configuration/NHFx False in the Engine config (with NHFx True only the four stock effects exist).
	Item {
		objectName: 'fixstream FX Select'

		EffectNames {
			id: names
		}

		Repeater {
			model: ListModel {
				Component.onCompleted: {
					const types = [
						{'note': 0, 'fxName': names.kEcho, 'shiftNames': [names.kHoldEcho, names.kPingPong, names.kReverseReverb, names.kEchoOut]},
						{'note': 1, 'fxName': names.kFlanger, 'shiftNames': [names.kCrush, names.kRecycler, names.kRiser, names.kFlexGate]},
						{'note': 2, 'fxName': names.kDelay, 'shiftNames': [names.kReverb, names.kSwellVerb, names.kReverbRise, names.kReverbDrop]},
						{'note': 3, 'fxName': names.kPhaser, 'shiftNames': [names.kBrake, names.kBackspin, names.kScaleDown, names.kStutterOut]},
					]
					for(const type of types) {
						append({'note': type.note, 'fxName': type.fxName, 'shiftNames': type.shiftNames.join('|')})
					}
				}
			}

			Item {
				readonly property var shiftNames: model.shiftNames.split('|')

				ValueNoteAssignment {
					objectName: 'FX %1'.arg(model.fxName)
					channel: fxConfig.midiChannel
					note: model.note
					output: QtObject {
						function setValue(channel, value, assignmentEnabled) {
							if(!assignmentEnabled || !value) {
								return
							}

							let fxName = model.fxName
							if(globalConfig.shift) {
								const current = shiftNames.indexOf(fxConfig.channel[fxConfig.channelNames[0]].fxType)
								fxName = shiftNames[(current + 1) % shiftNames.length]
							}
							for(const name of fxConfig.channelNames) {
								fxConfig.channel[name].pFxType.translator.string = fxName
							}
						}
					}
				}

				OutputAssignment {
					objectName: 'FX %1 LED'.arg(model.fxName)
					properties: { 'ledValue': '' }

					readonly property bool active: fxConfig.anyFxActive
					readonly property string fxType: fxConfig.channel[fxConfig.channelNames[0]].fxType
					readonly property bool assigned: fxType === model.fxName || shiftNames.indexOf(fxType) !== -1

					readonly property int ledValue: {
						if(fxConfig.fxEnabled) {
							if(assigned) {
								!active || (active && globalConfig.flashStateFast) ? 127 : 1
							}
							else {
								1
							}
						}
						else {
							0
						}
					}

					function send() {
						device.sendSimpleColor(fxConfig.midiChannel, model.note, ledValue)
					}

					Component.onCompleted: send()
				}
			}
		}
	}
