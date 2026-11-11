import {continueRender, delayRender, staticFile} from 'remotion';

// Loads Newsreader once, before any frame renders.
let loaded = false;
export const loadFonts = () => {
  if (loaded || typeof document === 'undefined') return;
  loaded = true;
  const handle = delayRender('Loading Newsreader');
  const faces = [
    new FontFace('Newsreader', `url(${staticFile('fonts/Newsreader.ttf')})`, {weight: '200 800', style: 'normal'}),
    new FontFace('Newsreader', `url(${staticFile('fonts/Newsreader-Italic.ttf')})`, {weight: '200 800', style: 'italic'}),
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
