import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { media } from "./design";
import { Hello } from "./scenes/Hello";
import { Level } from "./scenes/Level";
import { Presence } from "./scenes/Presence";
import { Words } from "./scenes/Words";
import { Keep } from "./scenes/Keep";
import { Story } from "./scenes/Story";
import { Outro } from "./scenes/Outro";
export const Film = () => (
  <>
    <Audio src={media("music-v2.m4a")} />
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={264} name="Hello">
        <Hello />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={354} name="Level">
        <Level />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={444} name="Presence">
        <Presence />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={474} name="Words">
        <Words />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={414} name="Keep">
        <Keep />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={234} name="Story">
        <Story />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={360} name="Outro">
        <Outro />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  </>
);
