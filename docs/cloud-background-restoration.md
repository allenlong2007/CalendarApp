# Portrait cloud restoration

2026-10-26. The original `CloudBackground` artwork crops the central cloud at
the source image's top edge. Removing the UI fade cannot recover those pixels.

Created `CloudBackgroundPortrait` with the built-in ImageGen tool. This is an
AI reconstruction of the missing crown, not recovery of original image data.
The existing source asset remains unchanged for landscape, iPad, and Mac.
Portrait rendering compensates for the taller canvas to preserve the scene's
scale and bottom clearance. Custom backgrounds keep using the imported image.

Asset: `CalendarApp/Resources/Assets.xcassets/CloudBackgroundPortrait.imageset/clouds-extended.png`.

## Generation prompt

Use case: precise-object-edit / upward canvas extension. Edit target: the provided 3000 x 1410 anime cloud landscape. The main central cloud is CUT OFF by the top edge. Extend the canvas UPWARD only, adding about 390 pixels of new content at the original scale (target composition equivalent to 3000 x 1800). Reconstruct the small missing rounded crown of the central cloud in the added space, continuing its exact painterly anime shape, highlights, and blue-white palette, with a clearly visible blue-sky margin above the entire cloud crown. All of the cloud silhouette must be inside the frame, never touching or clipped by the top edge. Preserve the original lower 1410px scene and all existing objects, character designs, character poses and positions, grass, fencing, sky streaks, colors, lighting, brushwork, detail, and horizontal framing as exactly as possible. Do not zoom or change the landscape composition; the only change is extra sky and completed cloud crown above the original top border. No text, no extra people, no new objects. This is a subtle restoration for an existing app wallpaper, not a redesign. Output the extended full landscape image, landscape aspect ratio 5:3.
