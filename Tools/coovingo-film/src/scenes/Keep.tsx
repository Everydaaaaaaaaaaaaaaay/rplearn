import { Paper, Headline, NativeScreen, FeatureRail } from "../design";
export const Keep = () => (
  <Paper>
    <Headline>把好表达，慢慢积累</Headline>
    <FeatureRail
      x={85}
      y={580}
      width={235}
      items={["cosy\n舒适惬意的", "shoreline\n海岸线", "单词 · 句子\n随时回看"]}
    />
    <NativeScreen
      file="09-favorites.png"
      x={365}
      y={350}
      width={630}
      angle={2}
    />
  </Paper>
);
