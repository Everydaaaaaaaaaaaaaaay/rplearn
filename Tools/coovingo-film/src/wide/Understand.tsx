import { Canvas, Copy, Phone } from "./design";
export const Understand = () => (
  <Canvas>
    <Copy
      title={"不懂的那一句，\n就从这里读懂。"}
      body={"聊天中随手查词，结合双语例句与发音，\n理解它在这段对话里的意思。"}
      width={1000}
      top={155}
    />
    <div
      style={{
        position: "absolute",
        left: 116,
        top: 655,
        fontSize: 70,
        fontWeight: 400,
        fontFamily: "Georgia,serif",
        color: "#286274",
      }}
    >
      a cosy café
    </div>
    <div
      style={{
        position: "absolute",
        left: 120,
        top: 752,
        fontSize: 31,
        opacity: 0.7,
      }}
    >
      一家舒适惬意的咖啡馆
    </div>
    <Phone file="03-dictionary.png" x={1290} y={80} w={425} />
  </Canvas>
);
