import { Canvas, Copy, Phone, DetailLine } from "./design";
export const Level = () => (
  <Canvas>
    <Copy
      title={"从你的水平出发，\n找到合适的难度。"}
      body={"选择当前英语水平，或完成自适应短测。\n让对话难度有据可依。"}
    />
    <DetailLine items={["词汇与语法", "阅读与听力", "短测给出难度建议"]} />
    <Phone file="10-level.png" x={1290} y={90} w={410} angle={2} />
  </Canvas>
);
