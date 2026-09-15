import { AbsoluteFill } from "remotion";
import { Eyebrow, Title, Note, Detail } from "../design";
export const Story = () => (
  <AbsoluteFill style={{ background: "#152d3a", overflow: "hidden" }}>
    <Eyebrow light>03 / 在故事里，找到自己的表达</Eyebrow>
    <Title light>
      每一次选择，
      <br />
      都是一次开口。
    </Title>
    <Note light>双语分支剧情，参与朋友的人生片段。</Note>
    <Detail file="08-story.png" top={565} height={450} crop={400} delay={28} />
    <Detail
      file="08-story.png"
      top={1050}
      height={780}
      crop={1370}
      delay={42}
    />
  </AbsoluteFill>
);
