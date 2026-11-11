import {continueRender, delayRender, staticFile} from 'remotion';

// Loads Newsreader (film, screenshots) and Charis SIL (banners) once, before any frame renders.
let loaded = false;
export const loadFonts = () => {
  if (loaded || typeof document === 'undefined') return;
  loaded = true;
  const handle = delayRender('Loading fonts');
  const faces = [
    new FontFace('Newsreader', `url(${staticFile('fonts/Newsreader.ttf')})`, {weight: '200 800', style: 'normal'}),
    new FontFace('Newsreader', `url(${staticFile('fonts/Newsreader-Italic.ttf')})`, {weight: '200 800', style: 'italic'}),
    ...(['Regular', 'Italic', 'Bold', 'BoldItalic'] as const).map(
      (name) =>
        new FontFace('Charis SIL', `url(${staticFile(`fonts/charis/CharisSIL-${name}.ttf`)})`, {
          weight: name.startsWith('Bold') ? '700' : '400',
          style: name.endsWith('Italic') ? 'italic' : 'normal',
        }),
    ),
  ];
  Promise.all(faces.map((face) => face.load()))
    .then((ready) => {
      ready.forEach((face) => (document.fonts as unknown as Set<FontFace>).add(face));
      continueRender(handle);
    })
    .catch((error) => {
      console.error(error);
      continueRender(handle);
    });
};
