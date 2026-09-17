import "./index.css";
import { Composition } from "remotion";
import { Film } from "./Film";
import { LandscapeFilm } from "./wide/LandscapeFilm";
export const RemotionRoot = () => (
  <>
    <Composition
      id="Coovingo"
      component={Film}
      durationInFrames={2400}
      fps={60}
      width={1080}
      height={1920}
    />
    <Composition
      id="CoovingoLandscape"
      component={LandscapeFilm}
      durationInFrames={3360}
      fps={60}
      width={1920}
      height={1080}
    />
  </>
);
