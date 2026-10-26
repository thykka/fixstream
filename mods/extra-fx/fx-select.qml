	// fixstream extra FX (5.x): the four FX select buttons, in place of the stock DJFxSelect block.
	// Press: the button's stock effect. Shift + press: the first effect of the button's extra list,
	// each further Shift press the next one, wrapping around.
	// LED: off while FX are disabled; bright when the selected effect is the button's (blinking while
	// an effect is on), dim otherwise.
	// Needs hasDJFx = 1 and hasNHFx = 0 in the Engine's NH08 config (engine-patch.py, patch dj-fx).
	Item {
		id: fxButtons
		objectName: "fixstream FX Select"

		// Every FX channel carries the same effect, so the first one stands for all
		readonly property string selected: fxConfig.channel[fxConfig.channelNames[0]].fxType

		function select(fx) {
			for (const name of fxConfig.channelNames) {
				fxConfig.channel[name].pFxType.translator.string = fx
			}
		}

		EffectNames {
			id: names
		}

		Repeater {
			// Set once, not bound: the EffectNames constants don't notify, so a binding would warn
			Component.onCompleted: model = [
				{ note: 0, fx: names.kEcho, extra: [names.kHoldEcho, names.kPingPong, names.kReverseReverb, names.kEchoOut] },
				{ note: 1, fx: names.kFlanger, extra: [names.kCrush, names.kRecycler, names.kRiser, names.kFlexGate] },
				{ note: 2, fx: names.kDelay, extra: [names.kReverb, names.kSwellVerb, names.kReverbRise, names.kReverbDrop] },
				{ note: 3, fx: names.kPhaser, extra: [names.kBrake, names.kBackspin, names.kScaleDown, names.kStutterOut] }
			]

			Item {
				id: fxButton
				readonly property int note: modelData.note
				readonly property string fx: modelData.fx
				readonly property var extra: modelData.extra
				readonly property bool owns: fxButtons.selected === fx || extra.indexOf(fxButtons.selected) !== -1

				// The extra effect after the selected one; the first if another effect is selected
				function nextExtra() {
					return extra[(extra.indexOf(fxButtons.selected) + 1) % extra.length]
				}

				ValueNoteAssignment {
					objectName: "FX %1".arg(fxButton.fx)
					channel: fxConfig.midiChannel
					note: fxButton.note
					output: QtObject {
						function setValue(channel, pressed, enabled) {
							if (enabled && pressed) {
								fxButtons.select(globalConfig.shift ? fxButton.nextExtra() : fxButton.fx)
							}
						}
					}
				}

				OutputAssignment {
					objectName: "FX %1 LED".arg(fxButton.fx)
					properties: { "ledValue": "" }

					readonly property bool bright: fxButton.owns && (globalConfig.flashStateFast || !fxConfig.anyFxActive)
					readonly property int ledValue: fxConfig.fxEnabled ? (bright ? 127 : 1) : 0

					function send() {
						device.sendSimpleColor(fxConfig.midiChannel, fxButton.note, ledValue)
					}

					Component.onCompleted: send()
				}
			}
		}
	}
