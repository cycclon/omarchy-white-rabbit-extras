# Contributing

Thanks for considering it. This is a personal theme shared in case it's
useful to someone else, not a project with a team behind it -- so the
process is deliberately small.

## The short version

1. Fork the repo.
2. Make your change on a branch.
3. Open a pull request describing what changed and why.
4. It gets reviewed and merged, asked for changes, or closed with an
   explanation. Every PR is read; not every PR is merged.

Forking, cloning, and running your own modified copy needs no permission --
the license already grants that. Getting a change merged back into this
repo is the one thing that goes through review.

## Before opening a PR

- **Say what you tested.** This repo touches Hyprland, Quickshell, and a
  native plugin with an unstable ABI -- "works for me" is fine, but say
  what "works" meant: which Omarchy/Hyprland version, whether you ran
  `install.sh` or hand-edited a live config, whether you saw it render.
- **Keep the theme-name gate pattern if you touch the plugins.** All three
  Quickshell plugins self-activate by comparing
  `~/.local/state/omarchy/current/theme.name` to `"white-rabbit"`. If
  you're adding a fourth plugin or a new file, match that pattern rather
  than introducing a different one.
- **Match the comment style.** The code comments explain *why*, not *what*
  -- especially in the rain plugin, where several non-obvious fixes
  (premultiplied-alpha texel packing, layer-shell remount culling) are
  documented right where they matter. If you fix something subtle, leave a
  comment future-you (or future-me) will thank you for.
- **Small, focused PRs review faster** than one PR that reworks three
  unrelated things. If you have three ideas, three PRs are easier to say
  yes to individually than one PR that's easy to reject as a whole.

## What's especially welcome

- New hidden words/phrases for the digital rain (the theme itself doesn't ship
  these -- see the README's "Adding your own words" section for the
  mechanism, and feel free to suggest additions to the built-in list in
  `plugins/cycclon.rain/RainModel.js`).
- Bug reports with a screenshot or a screen recording. Half of what this
  theme does is visual; "it looks wrong" is much easier to act on with a
  picture attached.
- Compatibility notes -- if you're on different Hyprland/Quickshell/Qt
  versions than the README's tested-on line and something breaks or
  works, that's useful either way.

## What's less likely to be merged

- Changes that drop the theme-name gate or make a plugin activate outside
  the White Rabbit theme by default -- that's the one design constraint
  this repo has.
- Anything that reintroduces `omarchy theme install`/raw `git clone`
  compatibility for the theme directory. See the README's "Install"
  section for why the theme is deliberately *not* installed that way.

## Reporting bugs without opening a PR

Opening an issue is fine and doesn't require touching any code. The most
useful bug reports include: your Omarchy/Hyprland/Quickshell versions
(`omarchy debug --no-sudo --print` covers most of it), what you expected,
what happened instead, and anything from
`journalctl --user -b | grep -i quickshell` around the time it happened
(run with `QT_FORCE_STDERR_LOGGING=1` set on the shell process if you can
reproduce it live -- see the README's Development section).
