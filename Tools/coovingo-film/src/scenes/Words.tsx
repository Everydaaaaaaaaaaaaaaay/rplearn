import { Paper, Headline, NativeScreen, FeatureRail } from "../design";
export const Words = () => (
  <Paper background="bg-desk.jpg">
    <Headline>让生词，在语境里读懂</Headline>
    <NativeScreen
      file="03-dictionary.png"
      x={355}
      y={335}
      width={655}
      angle={1}
    />
    <FeatureRail
      x={85}
      y={570}
      width={215}
      items={["随手查词", "双语例句", "聆听发音"]}
    />
  </Paper>
);
