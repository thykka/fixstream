			// Pitch bend buttons, replacing the stock PitchBend module (which can't be disabled per pad mode).
			// Auto Loop pad mode: beat jump back/forward; Shift = halve/double the jump size.
			// Other pad modes: stock behaviour (nudge; Shift = pitch range, swapped by the "Pitch Bend Action" preference).
			Repeater {
				model: ListModel {
					ListElement { note: 29; sign: "-"; direction: "Backward"; jump: "Back"; size: "Halve" }
					ListElement { note: 30; sign: "+"; direction: "Forward"; jump: "Forward"; size: "Double" }
				}

				Item {
					ValueNoteAssignment {
						objectName: "Pitch Bend %1 Deck%2".arg(model.sign).arg(deckConfig.name)
						note: model.note
						channel: deckConfig.midiChannel
						enabled: deckConfig.inDJMode && !deckConfig.padsModeIsAutoLoop && globalConfig.pitchBendActionIsNormal !== globalConfig.shift
						output: ActionOutput {
							target: PropertyTarget {
								path: deckConfig.activeDeckTrackPath + "Nudge%1".arg(model.direction)
							}
						}
					}

					ValueNoteAssignment {
						objectName: "Range %1 Deck%2".arg(model.sign).arg(deckConfig.name)
						note: model.note
						channel: deckConfig.midiChannel
						enabled: deckConfig.inDJMode && !deckConfig.padsModeIsAutoLoop && globalConfig.pitchBendActionIsNormal === globalConfig.shift
						output: IncDecValueOutput {
							target: PropertyTarget {
								path: deckConfig.activeDeckPath + "SpeedRange"
							}
							changeAmount: 1
							increaseValue: model.sign === "+"
							roundRobin: false
						}
					}

					ValueNoteAssignment {
						objectName: "Beat Jump %1 Deck%2".arg(model.jump).arg(deckConfig.name)
						note: model.note
						channel: deckConfig.midiChannel
						enabled: deckConfig.inDJMode && deckConfig.padsModeIsAutoLoop && !globalConfig.shift
						output: ActionOutput {
							target: PropertyTarget {
								path: deckConfig.activeDeckTrackPath + "BeatJump/Jump%1".arg(model.jump)
							}
						}
					}

					ValueNoteAssignment {
						objectName: "%1 Jump Size Deck%2".arg(model.size).arg(deckConfig.name)
						note: model.note
						channel: deckConfig.midiChannel
						enabled: deckConfig.inDJMode && deckConfig.padsModeIsAutoLoop && globalConfig.shift
						output: ActionOutput {
							target: PropertyTarget {
								path: deckConfig.activeDeckTrackPath + "BeatJump/BeatJump%1".arg(model.size)
							}
						}
					}
				}
			}
