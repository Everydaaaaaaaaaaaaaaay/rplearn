import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { Hello } from "./scenes/Hello";
import { Presence } from "./scenes/Presence";
import { Encounter } from "./scenes/Encounter";
import { Story } from "./scenes/Story";
import { Words } from "./scenes/Words";
import { Keep } from "./scenes/Keep";
import { Outro } from "./scenes/Outro";
import { media } from "./design";
export const Film = () => (
  <>
    <Audio src={media("music.m4a")} />
    <TransitionSeries>
      <TransitionSeries.Sequence
        durationInFrames={330}
        name="A reason to say hello"
      >
        <Hello />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence
        durationInFrames={570}
        name="Friends with their own rhythm"
      >
        <Presence />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence
        durationInFrames={390}
        name="Cities and encounters"
      >
        <Encounter />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence
        durationInFrames={390}
        name="Meaningful story choices"
      >
        <Story />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={390} name="Learn in context">
        <Words />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence
        durationInFrames={330}
        name="Keep useful expressions"
      >
        <Keep />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 24 })}
      />
      <TransitionSeries.Sequence durationInFrames={384} name="Coovingo">
        <Outro />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  </>
);
