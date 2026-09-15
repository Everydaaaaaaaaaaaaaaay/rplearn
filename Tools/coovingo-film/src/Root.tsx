import "./index.css";
import { Composition } from "remotion";
import { Film } from "./Film";
export const RemotionRoot = () => (
  <Composition
    id="Coovingo"
    component={Film}
    durationInFrames={2400}
    fps={60}
    width={1080}
    height={1920}
  />
);
