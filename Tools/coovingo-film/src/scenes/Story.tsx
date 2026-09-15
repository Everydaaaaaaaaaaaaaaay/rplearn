import { Paper, Headline, NativeScreen, FeatureRail } from "../design";
export const Story = () => (
  <Paper background="bg-bookshop.jpg" dark>
    <Headline>读进故事，做出选择</Headline>
    <NativeScreen file="08-story.png" x={80} y={345} width={685} angle={-1} />
    <FeatureRail
      x={815}
      y={720}
      width={180}
      dark
      items={["双语阅读", "分支选择", "情境表达"]}
    />
  </Paper>
);
