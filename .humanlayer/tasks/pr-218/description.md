## Why the change

The regular idle breathing looked too pronounced, so this reduces its scale change while preserving its existing cadence.

## Special things to note

- [x] User-visible UI change
- Only regular idle breathing is reduced; sleep breathing, timing, and the breathing preference remain unchanged.

![Idle breathing at 1.015×](./idle-breathing-1.015.gif)

## Change outline

The idle scale is lowered consistently when entering idle, restoring the animation, and applying the breathing preference.

```diff
- breathScale: 1.03
+ breathScale: 1.015
```

The animation test now expects `1.015` both when breathing is enabled and after the image is replaced.
