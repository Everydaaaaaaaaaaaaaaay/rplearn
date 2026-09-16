import { Canvas, Copy, Phone, DetailLine } from "./design";
export const Conversation = () => (
  <Canvas dark bg="bg-london.jpg">
    <Copy
      title={"想说的日常，\n就是练习的内容。"}
      body={
        "和不同性格的 AI 角色聊兴趣、聊近况。\n在有来有回的交流里，练习英语表达。"
      }
      top={200}
    />
    <DetailLine
      dark
      items={["有各自的经历与兴趣", "按当地作息联系", "自然打字、分条回复"]}
      top={810}
    />
    <Phone file="chat-motion.mp4" video x={1300} y={80} w={420} />
  </Canvas>
);
