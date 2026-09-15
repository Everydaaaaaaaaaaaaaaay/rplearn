import { Paper, Headline, NativeScreen, FeatureRail } from "../design";
export const Level = () => (
  <Paper>
    <Headline>从适合你的难度开始</Headline>
    <FeatureRail
      x={85}
      y={570}
      items={["词汇与语法", "阅读与听力", "自适应短测"]}
    />
    <NativeScreen file="10-level.png" x={372} y={370} width={615} angle={2} />
  </Paper>
);
