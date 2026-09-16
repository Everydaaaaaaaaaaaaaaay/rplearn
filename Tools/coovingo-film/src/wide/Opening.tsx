import { Canvas, Copy, Phone, DetailLine } from "./design";
export const Opening = () => (
  <Canvas dark bg="bg-london.jpg">
    <Copy
      kicker="咕游记 / COOVINGO"
      title={"把日常聊天，\n变成英语练习。"}
      body={"从读懂一句，到自然地接下一句。\n让学习发生在交流之中。"}
      top={180}
    />
    <Phone
      file="03-dictionary.png"
      x={1040}
      y={230}
      w={300}
      angle={-7}
      delay={22}
    />
    <Phone
      file="09-favorites.png"
      x={1555}
      y={230}
      w={300}
      angle={7}
      delay={34}
    />
    <Phone file="02-chat.png" x={1280} y={90} w={415} />
    <DetailLine
      dark
      items={["聊天 · 使用英语", "查词 · 理解语境", "收藏 · 积累表达"]}
      top={815}
    />
  </Canvas>
);
