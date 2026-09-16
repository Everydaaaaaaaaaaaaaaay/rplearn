import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { media } from "../design";
import { Opening } from "./Opening";
import { Level } from "./Level";
import { Conversation } from "./Conversation";
import { Understand } from "./Understand";
import { Collect } from "./Collect";
import { Explore } from "./Explore";
import { Places } from "./Places";
import { Story } from "./Story";
import { Closing } from "./Closing";
export const LandscapeFilm = () => (
  <>
    <Audio src={media("music-wide-56.m4a")} />
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={294} name="Opening">
        <Opening />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={324} name="Level">
        <Level />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={564} name="Conversation">
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
      <TransitionSeries.Sequence durationInFrames={324} name="Collect">
        <Collect />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={414} name="Explore">
        <Explore />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={414} name="Places">
        <Places />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={414} name="Story">
        <Story />
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
