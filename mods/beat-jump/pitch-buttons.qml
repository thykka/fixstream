			// fixstream beat jump (5.x): the pitch bend buttons, in place of the stock PitchBend block.
			// Auto Loop pad mode: jump back/forward; with Shift, halve/double the jump size.
			// Other pad modes: nudge; with Shift, pitch range (the "Pitch Bend Action" preference swaps the two).
			// The buttons have no LEDs, so nothing is sent back to them.
			Item {
				id: pitchButtons
				objectName: "fixstream Pitch Buttons %1".arg(deckConfig.name)

				readonly property bool jumpMode: deckConfig.inDJMode && deckConfig.padsModeIsAutoLoop
				readonly property bool bendMode: deckConfig.inDJMode && !deckConfig.padsModeIsAutoLoop
				// Range instead of nudge: with Shift, or without it when the preference swaps the two
				readonly property bool rangeAction: globalConfig.pitchBendActionIsNormal === globalConfig.shift

				Repeater {
					model: [
						{ note: 29, sign: "-", up: false, nudge: "Backward", jump: "Back", size: "Halve" },
						{ note: 30, sign: "+", up: true, nudge: "Forward", jump: "Forward", size: "Double" }
					]

					Item {
						id: button
						readonly property var side: modelData
						readonly property string deck: "Deck" + deckConfig.name
						readonly property string track: deckConfig.activeDeckTrackPath

						ValueNoteAssignment {
							objectName: "Pitch Bend %1 %2".arg(button.side.sign).arg(button.deck)
							channel: deckConfig.midiChannel
							note: button.side.note
							enabled: pitchButtons.bendMode && !pitchButtons.rangeAction
							resendValueOnEnabledChanged: false
							output: ActionOutput {
								target: PropertyTarget { path: button.track + "Nudge" + button.side.nudge }
							}
						}

						ValueNoteAssignment {
							objectName: "Range %1 %2".arg(button.side.sign).arg(button.deck)
							channel: deckConfig.midiChannel
							note: button.side.note
							enabled: pitchButtons.bendMode && pitchButtons.rangeAction
							output: IncDecValueOutput {
								target: PropertyTarget { path: deckConfig.activeDeckPath + "SpeedRange" }
								increaseValue: button.side.up
								changeAmount: 1
								roundRobin: false
							}
						}

						ValueNoteAssignment {
							objectName: "Beat Jump %1 %2".arg(button.side.jump).arg(button.deck)
							channel: deckConfig.midiChannel
							note: button.side.note
							enabled: pitchButtons.jumpMode && !globalConfig.shift
							output: ActionOutput {
								target: PropertyTarget { path: button.track + "BeatJump/Jump" + button.side.jump }
							}
						}

						ValueNoteAssignment {
							objectName: "%1 Jump Size %2".arg(button.side.size).arg(button.deck)
							channel: deckConfig.midiChannel
							note: button.side.note
							enabled: pitchButtons.jumpMode && globalConfig.shift
							output: ActionOutput {
								target: PropertyTarget { path: button.track + "BeatJump/BeatJump" + button.side.size }
							}
						}
					}
				}
			}
