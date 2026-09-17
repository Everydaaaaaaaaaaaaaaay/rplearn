import { Canvas, Copy, Phone, DetailLine } from "./design";
export const Story = () => (
  <Canvas dark bg="bg-bookshop.jpg">
    <Copy
      title={"读一段故事，\n选择你的下一句。"}
      body={"双语阅读，分支选择。\n在具体的处境里，尝试不同表达。"}
      top={210}
    />
    <DetailLine
      dark
      items={["原创故事", "英中对照", "选择推动故事"]}
      top={800}
    />
    <Phone file="08-story.png" x={1290} y={80} w={420} angle={-1} />
  </Canvas>
);
