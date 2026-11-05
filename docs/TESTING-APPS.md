# Testing the apps by hand

Build the apps (ad-hoc signed, fine on this Mac):

```sh
cmake --preset macos && cmake --build --preset macos
apps/scripts/package-macos.sh 1            # -> dist/3.0.24-1/VLCSyphon.app, VLCNDI.app
```

Or test the release DMGs from `apps/scripts/release-macos.sh 1`.

Each app keeps its own settings in `~/Library/Preferences/<bundle id>/vlcrc`. To repeat a
first launch, quit the app and remove them:

```sh
id=com.studioavante.vlcndi    # or com.studioavante.vlcsyphon
defaults delete $id; rm -rf ~/Library/Preferences/$id ~/Library/Application\ Support/$id ~/Library/Caches/$id ~/Library/HTTPStorages/$id
```

## VLCSyphon.app

- [ ] First launch (open a video file directly with the app) shows no "album art and metadata"
      question, and the video opens in its own window.
- [ ] Right after launch, with nothing playing, a Syphon client already lists
      **VLCSyphon – Video**: 1920×1080, fully transparent.
- [ ] Play a video. A Syphon client (Resolume, MadMapper, OBS, Syphon Simple Client) lists
      **VLCSyphon – Video**, and the picture plays in VLC's window at the same time.
- [ ] Preferences ▸ Show All ▸ Video ▸ Filters: **Syphon** is ticked. While a video plays,
      untick it and Save: within a second the server is gone and the video keeps playing.
      Tick it and Save: the server is back, showing the playing video. No restart needed.
- [ ] Preferences ▸ Video ▸ Filters ▸ Syphon: change the server name; clients show the new name.
- [ ] Video opens in its own window, not inside the main (playlist) window.
- [ ] The interface is dark.
- [ ] Cmd-Tab and the Dock show the app's own icon. (On a dev Mac that ran older builds from the
      same path, run `killall Dock` once if the switcher still shows an old icon.)
- [ ] Play a file with a different resolution: the server follows it.
- [ ] Close the video window (or Stop): the server stays, fully transparent at the same size.
- [ ] At the end of a file the video window closes and the server stays, fully transparent at
      the same size.
- [ ] Turn Play and pause on (Preferences ▸ Show All ▸ Playlist): at the end of a file the video
      stays on its last frame and Syphon clients keep it.
- [ ] The official VLC (if installed) is unaffected: no Syphon, its settings unchanged.
- [ ] The menu bar and Dock show VLCSyphon with the orange icon. "Check for Updates" never
      replaces the app with plain VLC (expect an error).

## VLCNDI.app, before installing the NDI runtime

- [ ] Play a video. VLC shows **one** error: "NDI 6 Runtime not found … Install the NDI Runtime
      for macOS (libNDI_for_Mac.pkg) from http://ndi.link/NDIRedistV6Apple, then restart". Playback
      continues normally. (Installing NDI Tools doesn't change this: only the runtime counts.)
- [ ] Open a second file in the same session: no second error.

## VLCNDI.app, after installing the NDI Runtime (http://ndi.link/NDIRedistV6Apple)

- [ ] macOS asks to allow VLCNDI on the local network: Allow.
- [ ] Right after launch, with nothing playing, receivers list **<COMPUTER> (VLC)**: 1920×1080
      fully transparent. The same lifetime rules as Syphon apply (last frame, transparent when
      video closes).
- [ ] Play a video with sound. NDI Studio Monitor / NDI Video Monitor (from NDI Tools), OBS
      with DistroAV, or vMix lists **<COMPUTER> (VLC)** with picture and sound in sync.
- [ ] Preferences: **NDI** is ticked under Video ▸ Filters and Audio ▸ Filters. Untick both:
      the source disappears after the next playback start.
- [ ] Both: enable Syphon too in VLCNDI (Video ▸ Filters ▸ Syphon): Syphon and NDI at once.
- [ ] SD video (a DVD rip, 720×576) shows correct colours in the receiver.

## Things to report

VLC's log helps: Window ▸ Messages (set verbosity to 2), or run from Terminal:

```sh
dist/3.0.24-1/VLCNDI.app/Contents/MacOS/VLCNDI -vv movie.mp4
```
