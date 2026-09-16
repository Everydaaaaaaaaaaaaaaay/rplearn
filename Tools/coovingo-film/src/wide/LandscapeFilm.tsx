import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { media } from "../design";
import { Opening } from "./Opening";
import { Level } from "./Level";
import { Conversation } from "./Conversation";
import { Understand } from "./Understand";
import { Collect } from "./Collect";
import { Places } from "./Places";
import { Closing } from "./Closing";
export const LandscapeFilm = () => (
  <>
    <Audio src={media("music.m4a")} />
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={300} name="Opening">
        <Opening />
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
      <TransitionSeries.Sequence durationInFrames={510} name="Conversation">
        <Conversation />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={444} name="Understand">
        <Understand />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={414} name="Collect">
        <Collect />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={402} name="Places">
        <Places />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={360} name="Closing">
        <Closing />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  </>
);
