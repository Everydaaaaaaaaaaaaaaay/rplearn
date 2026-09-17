import { Canvas, Copy, Phone, DetailLine } from "./design";
export const Collect = () => (
  <Canvas>
    <Copy
      title={"聊过的好表达，\n留下来，慢慢用。"}
      body={
        "把有用的单词和句子放进收藏。\n让每一次聊天，都留下可以回看的积累。"
      }
      top={180}
    />
    <DetailLine
      items={["cosy\n舒适惬意的", "shoreline\n海岸线", "单词与句子\n集中回看"]}
      top={785}
    />
    <Phone file="09-favorites.png" x={1290} y={80} w={425} angle={-1} />
  </Canvas>
);
