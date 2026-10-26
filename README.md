# fixstream

New features for the Numark Mixstream Pro. fixstream takes the official firmware update and adds the features below. You then install the result like any normal update.

Works only with firmware **5.0.4**. Not made or supported by Numark or inMusic. **Use at your own risk.**

## Which version?

fixstream supports two firmware versions. Use the one that matches the firmware you want to run:

- **5.0.4**: this page.
- **4.3.4**: [fixstream v1.0.0](https://github.com/thykka/fixstream/tree/v1.0.0).

Moving from 4.x to 5.x affects your library; see [Your Engine DJ library](#your-engine-dj-library) first.

## Features

- **Beat jump.** In Auto Loop pad mode, the pitch bend `−` / `+` buttons jump back and forward. Hold `SHIFT` to halve or double the jump size, which is shown on screen. In other pad modes the buttons work as normal.
- **Extra effects.** Hold `SHIFT` and press an FX button to pick one of four extra effects. Press again to cycle through them. Without Shift, the buttons work as normal.
  - Echo: Hold Echo, Ping Pong, Reverse Reverb, Echo Out
  - Flanger: Crush, Recycler, Riser, Flex Gate
  - Delay: Reverb, Swell Verb, Reverb Rise, Reverb Drop
  - Phaser: Brake, Backspin, Scale Down, Stutter Out
- **Custom start-up screen.**

## What you need

- A Mac (Linux might work, but isn't fully tested)
- A USB stick or SD card
- About 2 GB of free disk space

## Step 1: Create the firmware

1. Install [Homebrew](https://brew.sh) by following the instructions on its website.
2. Open the *Terminal* app and paste this command, then press Return:
   ```bash
   brew install e2fsprogs xz ffmpeg
   ```
3. Download the Mixstream Pro firmware update, **version 5.0.4**, from [enginedj.com/downloads](https://enginedj.com/downloads). You need the file named `MIXSTREAMPRO-5.0.4-Update.img`. The patch will not work with any other version.
4. Download fixstream from the [Releases](https://github.com/thykka/fixstream/releases) page (**Source code (zip)**) and unzip it.
5. In Terminal, type `cd ` (with a space after it), drag the fixstream folder into the Terminal window, and press Return.
6. Type `bash patch.sh ` (with a space after it), drag the firmware file from step 3 into the Terminal window, and press Return.

This takes a few minutes. When it's done, the new firmware can be found inside the `out` folder. It has the same name as the original file on purpose, don't rename it!

If you'd rather skip a feature, add `--no-beat-jump`, `--no-extra-fx` or `--no-splash` to the end of the command in step 6.

## Step 2: Install it

1. Plug the unit into mains power. **Don't switch it off during the update.** If the update is interrupted, the unit may not start until you restore it (see below).
2. Copy the new firmware from the `out` folder to a USB stick or SD card. Put it directly on the stick or card, not inside a folder, and don't rename it.
3. Insert it into the unit and go to **Settings > About/Update > Options > USB/SD**.

If you need to go back to the original firmware, just install the original 5.0.4 file the same way.

## Your Engine DJ library

Engine DJ libraries from 5.x don't work on 4.x, and as far as we know they can't be converted back. If you're on 4.x, back up your library before moving to 5.x. If you go from 5.x back to 4.x, you may need to rebuild your library.

## If the unit doesn't start

Restore the original firmware:

1. Plug the unit into mains power and remove any SD card or USB stick.
2. On the left deck, hold **Cue + Saved Loop + Auto Loop** and press power. The screen shows the Engine DJ logo with a download icon.
3. Connect the unit to your computer with a USB cable. Run the official Mixstream Pro updater from [enginedj.com/downloads](https://enginedj.com/downloads).

## Good to know

- Your settings, Engine DJ login and stems license are kept. A **factory reset**, however, erases your stems license, with or without fixstream.
- Installing an official firmware update removes fixstream's features.
- Modified firmware voids your warranty. In the worst case, the unit may not start until you restore the original firmware.

## License

[GPL-3.0](LICENSE). This project contains no files from Numark or inMusic.
